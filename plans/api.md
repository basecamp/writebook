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

Repeated edits inside 10 minutes coalesce. **But the no-change detection is
broken for Pages**: `will_change_leafable?` compares `leafable.attributes[key]`,
and a Page's body is a `has_markdown` association, not a column — so
`attributes["body"]` is always nil and any submitted body counts as a change.
Re-sending 45 unchanged pages on a push more than 10 minutes after the last one
would record 45 junk revisions, each duplicating the Page and its Markdown row
(`update_and_record_edit` dups the leafable). Fix it in the model — compare
`leafable.body.content.to_s` for markdown attributes — so the web UI benefits
too. Sections are unaffected (`body` is a real column). With that fixed, the
cheap-resync property holds — **provided the API goes through `Leaf#edit` and
not `page.update!`**.

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

Show and reset the key on the profile edit page, alongside the session transfer
link it resembles — never on the profile show page, which everyone in the account
can see. Note that
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

Sections are writable in v1 — the Omarchy manual's four part dividers are
Sections and currently exist nowhere in git. They don't need round-trip; they
stay writable with a plain JSON body (`title`, `body`, `theme`) —
`Section#markable` is a bare string anyway. In the repo a section is a file like
any other leaf, marked `type: section` in its front matter; the sync script reads
that to pick the endpoint. The one JSON read endpoint is the manifest: `id`,
`leafable_type`, `title`, `slug`, `position`, `external_id` per leaf.

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

Add `external_id` (string, nullable) to `leaves`, unique per book. Upsert rides
the front matter: a `POST` whose document carries `external_id:` finds-or-creates
by it. No dedicated `/by_external_id/` route — the key contains `.`, which would
fight the router's format parsing.

Without this the client must keep its own filename→leaf-ID map, which drifts the
first time someone edits in the web UI, and makes renames indistinguishable from
delete+create. The Omarchy sync sets it to the filename with the ordering prefix
stripped: `27-monitors.md` → `monitors.md`. The prefix carries position, the name
carries identity — so renumbering files to reorder or insert pages (the common
case) doesn't churn identity, leaf ids, or published URLs. A true rename still
reads as delete+create: rare, and acceptable. Two files sharing a stripped name
collide on the unique index, which fails the sync loudly — an authoring error,
correctly rejected.

Deletes should trash, not destroy — `Leaf` already has `status: %w[active trashed]`
and `Leaf::Editable#record_moved_to_trash` logs it. A bad sync must be recoverable.
A trashed leaf keeps its `external_id`, so upsert must match trashed leaves too
and restore them (back to `active`, then `Leaf#edit`) rather than collide with the
unique index — a bad sync that trashed pages heals itself on the next good push.

**Git always wins.** The sync trashes leaves absent from the repo and overwrites
web-UI edits on the next push. Soft-trash and the revision history make both
recoverable. This makes web editing of a mirrored book advisory — that's the
simplicity trade, made deliberately.

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

**Uploads return absolute URLs, and the editor inserts them.** Today the editor
inserts the relative `/u/<slug>` path — `create.json.jbuilder` renders `fileUrl`
from `Attachment#slug_path` (`lib/rails_ext/active_storage_sluggable.rb:8`).
Switch that to the full URL (`action_text_markdown_upload_url`) so bodies carry
the same explicit URL the git source does. Images then render on GitHub and in
local editors, and the byte-for-byte round trip holds with no rewriting on either
side. The cost is baking the canonical host into stored bodies — a domain move
needs a one-time rewrite. Existing bodies hold relative paths; normalize the
manual's once during the initial export to git.

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
- Upsert by `external_id` updates rather than duplicating, and restores a
  trashed match instead of colliding with the unique index.
- `GET` then `PUT` of an untouched leaf `.md` is a no-op, and a title containing
  `"` survives the round trip.
- Upload returns a `/u/...` URL that `#show` then serves.

## Out of scope

Picture leaves, book create/destroy, user management, and reading via JSON beyond
the manifest needed to sync.
