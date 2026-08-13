# A write API for Writebook

## Goal

Let a book be maintained in a git repo and mirrored into Writebook by a script,
without a shell account on the box. Read access already exists; this plan adds
the write half and the authentication to use it.

The driving use case is the Omarchy manual, whose authoritative source is moving
to `basecamp/omarchy` under `manual/` (45 pages, one file per leaf, ordered by
filename prefix). A push to that repo should update learn.omacom.io.

## What already exists

Most of the pieces are here and unexposed. Read the following before starting.

**The read half is done.** `BooksController#show` and `LeafablesController#show`
both `respond_to { format.md }` under `allow_unauthenticated_access`, rendering
`app/views/books/show.md.erb` and `app/views/leafables/show.md.erb`. That is where
`https://learn.omacom.io/2/the-omarchy-manual.md` comes from.

**CSRF exemption for keyed clients is already wired, and dead.**
`app/controllers/concerns/authentication.rb:9`:

```ruby
protect_from_forgery with: :exception, unless: -> { authenticated_by.bot_key? }
```

Nothing in this repo ever calls `set_authenticated_by(:bot_key)`, so the branch is
unreachable. Writebook inherited the guard from the shared ONCE `Authentication`
concern without the implementation. Campfire has the other half.

**Correct upsert semantics already exist.** `Leaf::Editable#edit` (`app/models/leaf/editable.rb`)
is what the API must call:

```ruby
MINIMUM_TIME_BETWEEN_VERSIONS = 10.minutes

def record_new_edit?(leafable_params)
  will_change_leafable?(leafable_params) && last_edit_old?
end
```

An unchanged page records no revision, and repeated edits inside 10 minutes
coalesce. A sync that re-sends all 45 pages on every push is therefore cheap and
does not shred the revision history — **provided it goes through `Leaf#edit` and
not `page.update!`**. This is the single easiest thing to get wrong.

**Other relevant API:** `Book#press(leafable, leaf_params)` creates a leaf;
`Positionable#move_to_position(offset)` reorders; `Leaf#slug` is
`title.parameterize`; URLs are `/:book_id/:book_slug/:id/:slug`.

## What's missing

1. No way to authenticate a non-browser client.
2. No write endpoints.
3. No stable key to upsert against.
4. No upload path usable without a browser session.

## Design

### 1. Authentication: a personal bearer key

No bot users, no role changes. Every user gets a resettable API key:

```ruby
has_secure_token :bearer_key    # Session already uses has_secure_token
```

Authenticate from the `Authorization: Bearer <key>` header (no path/param key —
those land in logs, `Referer`, and proxy traces):

```ruby
def restore_authentication
  if session = find_session_by_cookie
    resume_session session
  elsif user = authenticate_with_http_token { |token, _| User.active.find_by(bearer_key: token) }
    Current.user = user
    set_authenticated_by :bearer_key
  end
end
```

`Current` has a `user` attribute settable independently of `session`
(`app/models/current.rb`), so no `Session` row is involved. Scoping the lookup to
`User.active` means deactivating a user kills their key, and
`user.regenerate_bearer_key` (free with `has_secure_token`) handles resets.

Because the key resolves to a real `User`, **the existing `Access` rows and
`book.editable?` checks keep working untouched**, including in
`ActionText::Markdown::UploadsController`. Do not invent a parallel authorization
path. Per-book scoping falls out too: the Omarchy mirror runs as a dedicated
ordinary user (say, "Omarchy Sync") holding an editor `Access` row on just the
manual — no new mechanism.

**Default-deny stays, reshaped.** A bearer key lives in CI secrets and scripts, so
it is far leakier than a session cookie; it must not be a full session equivalent.
Keep Campfire's shape but keyed to the header auth:

```ruby
before_action :deny_bearer_keys                # default deny
def deny_bearer_keys = head :forbidden if authenticated_by.bearer_key?
```

with `allow_bearer_key_access` to opt in the API controllers (and the new uploads
route) only. This makes the dead CSRF guard at
`app/controllers/concerns/authentication.rb:9` live — rename its `bot_key?`
inquiry to `bearer_key?` to match.

Expose show/reset on the existing user profile (`Users::ProfilesController`);
until then, `regenerate_bearer_key` from the console is enough. Note that
`request_authentication` redirects to login — the bearer path must render
`head :unauthorized` for API requests instead of a 302.

### 2. Representation: the leaf `.md` document round-trips; JSON only for the manifest

Round-trip is scoped to leaves. The book-level `.md` stays a lossy, human-facing
export (`Book#markable` joins with `"\n\n"`, sections are indistinguishable from
prose) — the sync never reads it.

The per-leaf `.md` (`app/views/leafables/show.md.erb`) is already the right
document: front matter (`title`, `url`) plus the raw body, and `has_markdown`
stores body as verbatim markdown source, so it round-trips byte-for-byte. Writes
accept the same format (`Content-Type: text/markdown`) instead of JSON-wrapping
markdown in strings. `PUT` back what you `GET`, edited.

To make the round trip exact:

- **Escape the title.** `title: "<%= @leaf.title %>"` emits invalid YAML when the
  title contains `"`. Emit a JSON-encoded string (valid YAML) and parse it back.
- **Fix the parsing rule.** Front matter is required on write, starts at byte 0,
  and ends at the first `\n---\n`; everything after is body, verbatim. Bodies
  containing `---` lines survive.
- **`url:` is output-only.** Ignore it (and any unknown keys) on write. Accept
  optional `position` and `external_id` keys.
- **No whitespace drift.** The serializer must not append newlines the parser
  drops, or every sync run looks like a change.

Sections don't need round-trip; they stay writable with a plain JSON body
(`title`, `body`, `theme`) — `Section#markable` is a bare string anyway. The one
JSON read endpoint is the manifest: `id`, `leafable_type`, `title`, `slug`,
`position`, `external_id` per leaf.

### 3. Endpoints

Nest under the existing `resources :books` in `config/routes.rb`, opted in with
`allow_bearer_key_access`:

```
GET    /books/:book_id/leaves.json          # ordered manifest: id, type, title, slug, position, external_id
POST   /books/:book_id/pages.md             # create from a leaf .md document (Book#press)
PUT    /books/:book_id/pages/:id.md         # update via Leaf#edit, same document format
DELETE /books/:book_id/pages/:id            # Leaf#trashed! (soft, already how destroy works)
POST   /books/:book_id/pages/:id/uploads.json
```

Reading a leaf already works: `GET /:book_id/:book_slug/:id/:slug.md`. The write
side parses `request.raw_post` per the rules in §2 — the `:md` mime type is
registered, but Rails won't parse a markdown request body into `params`.

`sections` get the same routes with JSON bodies. `pictures` can wait — the
Omarchy manual uses inline markdown images, not Picture leaves.

Reuse `SetBookLeaf`, which already gives `set_book` (`Book.accessable_or_published`),
`set_leaf` (`@book.leaves.active`), and `ensure_editable`.

### 4. Upsert key

Add `external_id` (string, nullable) to `leaves`, unique per book. Support upsert
by it, e.g. `PUT /books/:book_id/leaves/by_external_id/:external_id.json`, or a
`external_id` field on create that finds-or-creates.

Without this the client must keep its own filename→leaf-ID map, which drifts the
first time someone edits in the web UI, and makes renames indistinguishable from
delete+create. The Omarchy sync would set `external_id` to the repo-relative path
(`manual/27-monitors.md`).

Deletes should trash, not destroy — `Leaf` already has `status: %w[active trashed]`
and `Leaf::Editable#record_moved_to_trash` logs it. A bad sync must be recoverable.

### 5. Uploads

`ActionText::Markdown::UploadsController#create` currently requires a signed
GlobalID minted into the editor:

```ruby
@record = GlobalID::Locator.locate_signed params[:record_gid],
  only: Page, for: ActionText::Markdown::UPLOADS_SIGNED_ID_PURPOSE
```

There is no way for a script to obtain one. Add a bearer-key-authenticated route
that resolves the page from `:book_id`/`:id` instead, authorizes with the existing
`ensure_editable`, and otherwise reuses the same attach-and-render path. Return the
`/u/...` URL.

Serving already works for this use case: `#show` is `allow_unauthenticated_access`
and sets `expires_in 1.year, public: true` for published books, so the URLs render
on GitHub and cache well.

### 6. Positioning

Accept `position` on create/update and apply via `move_to_position`. Don't write
`position_score` directly — `Positionable` owns the gap arithmetic and the
`REBALANCE_THRESHOLD` rebalance.

## Migrations

1. `leaves.external_id` (string, index unique on `[book_id, external_id]`).
2. `users.bearer_key` (string, unique index). `has_secure_token` only generates on
   create, so backfill existing users in the migration
   (`User.find_each(&:regenerate_bearer_key)`).

## Testing

Per `AGENTS.md`: prefer existing fixtures (`leaves(:welcome_page)`), use `_path`
helpers, and `assert_in_body` / `assert_not_in_body`.

Cover at minimum:

- A bearer key authenticates and CSRF is skipped; a bad, reset, or deactivated
  user's key gets `:unauthorized` (not a redirect).
- `deny_bearer_keys` blocks a valid key on a non-API controller (regression guard
  for the default-deny above).
- A key whose user has no `Access` to a private book gets `:forbidden`.
- Re-sending identical content records **no** new `Edit`.
- Two edits inside `MINIMUM_TIME_BETWEEN_VERSIONS` produce one revision.
- Upsert by `external_id` updates rather than duplicating.
- `GET` then `PUT` of an untouched leaf `.md` is a no-op, and a title containing
  `"` survives the round trip.
- Upload returns a `/u/...` URL that `#show` then serves.

## Open questions

- **Should Sections be writable in v1?** The Omarchy manual needs them, since its
  four part dividers are Sections and currently exist nowhere in git.

## Out of scope

Picture leaves, book create/destroy, user management, and reading via JSON beyond
the manifest needed to sync.
