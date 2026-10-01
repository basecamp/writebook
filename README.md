# Writebook

### Instantly publish your own books on the web for free, no publisher required.

> **This is a fork of [basecamp/writebook](https://github.com/basecamp/writebook)**
> that adds a **static site generator**: export the public library to a
> self-contained static HTML site you can host anywhere — no Rails process,
> login, or editing machinery. See **[STATIC_SITE_GENERATOR.md](./STATIC_SITE_GENERATOR.md)**
> for the full guide, or the quick summary below.

Writebook is an easy-to-use application for publishing content on the web.
Content is authored in Markdown, and books can contain picture pages, chapters, and title pages.
Books can be published privately or publicly, and are searchable.

## How to get Writebook

Writebook is distributed as a Docker image.
The simplest way to install and run it is by using [ONCE](https://github.com/basecamp/once).

To get started, paste this snippet into a terminal on the machine where you want to install Writebook:

```sh
curl https://get.once.com/writebook | sh
```

## Deploying manually with Docker

If you'd rather set the Docker image up yourself, you can use `docker run` or `docker compose` to do that.
The official image is `ghcr.io/basecamp/writebook`.

You'll need to route the incoming web traffic to ports 80 and 443 (or just 80 if you run without SSL).
To persist the storage of the application, mount a Docker volume to `/rails/storage`.

You can configure the SSL setting with the following environment variables:

- `SSL_DOMAIN` - enable automatic SSL via Let's Encrypt for the given domain name
- `DISABLE_SSL` - alternatively, set `DISABLE_SSL` to serve over plain HTTP

## Running in development

Install dependencies:

```sh
bin/setup
```

Start the development server:

```sh
bin/dev
```

## Static site generator (this fork)

Render the published library to a static HTML directory you can host anywhere —
all books, every page, all CSS/JS and image files copied in, no login or editing
machinery.

**From the admin UI:** an admin-only **Export to static site** button in the
library header opens a landing page where you pick a scope — **all published
books** (optionally including unpublished drafts) or **a single book** to export
by itself. It runs the export and shows a result page with the file counts and
what to do next (where the files are, how to preview locally, how to deploy),
plus a **Download .zip** button (`writebook-static-site.zip`, or
`writebook-<slug>.zip` for a single book) and a **Preview site** button. The
live database is never touched — the export runs inside a rolled-back
transaction.

**From the command line:**

```sh
bin/rails static:generate                                  # → tmp/static-site
STATIC_HOST=books.example.com bin/rails static:generate    # absolute URLs → this host
STATIC_ALL=1 bin/rails static:generate                      # include unpublished books (DB untouched)
```

See **[STATIC_SITE_GENERATOR.md](./STATIC_SITE_GENERATOR.md)** for what's
included, the design principles, and the file map.
