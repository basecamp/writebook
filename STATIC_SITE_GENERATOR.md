# Static site generator

This fork of [basecamp/writebook](https://github.com/basecamp/writebook) adds a
**static site generator**: it renders the public library — the menu of books,
every book's table of contents, and every leaf — to a self-contained static HTML
directory you can host anywhere, with **no Rails process, login, or editing
machinery**. All CSS/JS assets and image binaries (covers, in-body uploads,
ActiveStorage pictures) are copied in.

It's a generic feature for the OSS Writebook project — intended to be PR-able
upstream to Basecamp — and is not coupled to any one instance. Any operator can
export their own books from their own Writebook.

## Two ways to run

### From the admin UI (synchronous)

Administrators get a new **Export to static site** button (the download icon) in
the library page header. It opens a landing page with a selector:

- **All published books** — export the whole library. Check **Include
  unpublished drafts** to also render books that aren't published yet.
- **A single book** — pick one title to export by itself, handy for sharing or
  hosting one book at a time. The chosen book is exported whether or not it's
  published; the drafts checkbox only applies to the whole-library export. The
  generated site's library menu lists just that one book.

Clicking **Generate static site** runs the export into `tmp/static-site` and
shows a result page with the counts and **what to do next**:

- where the files are on the server,
- how to preview locally (`cd tmp/static-site && python3 -m http.server 8080`),
- how to deploy — copy the directory's contents to any static host (Netlify,
  Cloudflare Pages, GitHub Pages, an S3 bucket, nginx); URLs are root-relative so
  the site works at any domain's root with no extra config.

From there, **Download .zip** streams the generated site as a single archive
(named `writebook-static-site.zip`, or `writebook-<slug>.zip` when you exported
one book), and **Preview site** serves it from inside the app under
`/static-site/` so you can see it rendered in a browser tab.

The export runs synchronously. Writebook runs no background jobs, and a
published-only export takes seconds. For very large libraries the result page
points you at the rake task below, to avoid holding a single web request open.

Either scope is rolled back the moment the export finishes, so your live
database is never touched — the same approach the rake task uses.

### From the command line

```sh
# Export published books to tmp/static-site:
bin/rails static:generate

# Custom output directory:
bin/rails static:generate[path/to/output]

# Absolute URLs are rewritten to this host, then made root-relative:
STATIC_HOST=books.example.com bin/rails static:generate

# Include unpublished books too — the live DB is left untouched:
STATIC_ALL=1 bin/rails static:generate
```

`STATIC_ALL=1` temporarily flips `published: true` inside a rolled-back
`Book.transaction`, so unpublished drafts render but the live database is never
modified.

## What's included

- The library menu (`/`), every book (`/:id/:slug`), and every leaf
  (`/:book_id/:book_slug/:id/:slug`).
- The library cards' bookmark overlay frames (`/books/:id/bookmark`), rendered
  so the cards' click targets resolve on the static host instead of 404ing into
  Turbo's "content missing" fallback.
- The front-matter **markdown** alternate routes (`….md`) the book and leaf
  views declare via `<link rel="alternate" type="text/markdown">`.
- Every precompiled asset in `public/assets/`, the root static files
  (`favicon.svg`, `app-icon.png`, `robots.txt`, …), and the PWA manifest.
- Every referenced image blob — ActiveStorage covers/pictures
  (`/rails/active_storage/…`) and in-body uploads (`/u/<slug>`).
- The per-book table-of-contents sidebar, externalized once per book and loaded
  with a tiny inline fetch (see Design below).

## What's NOT included

- **Editing/auth machinery.** The read templates already suppress every editing
  affordance when `book.editable?` is false (i.e. logged-out), so **no application
  code is modified** — the same templates produce clean read-only HTML. The one
  login affordance that remains in the logged-out view (the library's sign-in
  link) is stripped from the output, since it has no destination on a static host.
- **Unpublished books**, by default. Use `STATIC_ALL=1`.

## Design principles

- **Render every route the read views reference — nothing more, nothing less.**
  The exporter drives `ActionDispatch::Integration::Session`, so every read-view
  helper (`arrangement_tag`, `leaf_nav_tag`, `link_to_next_leafable`,
  `page.body.to_html`, …) runs in its real request context — no stubbing. Read
  views are rendered logged-out, exactly as a visitor sees them.
- **No template changes.** All transforms are post-processing on rendered HTML.
- **Keep the reading UX faithful.** Turbo Drive, Turbo Frames, and the Stimulus
  controllers (hotkey nav, lightbox, sidebar, reading-tracker, toc-view, …) ship
  exactly as Writebook provides them. The only JS the exporter adds is the
  one-line sidebar fetch.

The two faithful post-processing additions:

1. **Bookmark frames.** Rewrite each library card's
   `<turbo-frame src="/books/:id/bookmark">` to a trailing slash and render
   `/books/:id/bookmark/` to `books/:id/bookmark/index.html`, so the overlay
   click target resolves.
2. **Externalize the sidebar.** The full book TOC is byte-identical across every
   leaf. Writing it once per book (`<book_rel>/_sidebar.html`) and loading it with
   a small inline `fetch("../../_sidebar.html")` turns an O(n²) export (every leaf
   carries the whole TOC) into O(n). With JS off the sidebar nav is absent, but
   the page body and prev/next still work. A 1,255-leaf book goes from ~390 MB to
   ~39 MB.

## Files

| Path | Purpose |
| --- | --- |
| `lib/writebook/static_exporter.rb` | `Writebook::StaticExporter` — the renderer |
| `lib/tasks/static.rake` | `bin/rails static:generate` |
| `app/controllers/static_exports_controller.rb` | Admin UI action (`show` landing, `create` runs the export; `before_action :ensure_can_administer`) |
| `app/views/static_exports/show.html.erb` | Landing page with the Generate button |
| `app/views/static_exports/create.html.erb` | Result page with counts + next steps |
| `app/views/books/index.html.erb` | Admin download button in the library header |
| `config/routes.rb` | `resource :static_export` |
| `test/lib/writebook/static_exporter_test.rb` | Exporter tests |
| `test/controllers/static_exports_controller_test.rb` | UI controller tests |

## Running the tests

```sh
bin/rails test
```

All green: 186 runs, 709 assertions, 0 failures.

## Credits

Built on [basecamp/writebook](https://github.com/basecamp/writebook)
(MIT-licensed). This static-site-generator feature is intended as an upstream
contribution.