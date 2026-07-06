require "uri"

module Writebook
  # Renders Writebook's read-only views -- the library menu, each book's table of
  # contents, and every leaf -- to a static directory, along with every asset and
  # image blob those pages reference. The result can be served by any static web
  # server with no Rails process, login, or editing machinery.
  #
  # Books are rendered exactly as a logged-out visitor sees them. The read
  # templates already suppress every editing affordance when +book.editable?+ is
  # false, so no application code is modified. The single login affordance that
  # remains in that view -- the library's sign-in button -- is stripped from the
  # output, since it has no destination on a static host. Absolute URLs to the
  # export host are rewritten to be root-relative so the site is self-contained.
  #
  # Resources (compiled assets and image blobs) are resolved two ways:
  #   * In a deployed instance, +public/assets+ already holds the precompiled
  #     asset files, so that directory is mirrored directly.
  #   * Anything referenced by the rendered pages that the mirror did not
  #     already provide -- e.g. assets served live by Propshaft in development,
  #     ActiveStorage covers/pictures, and in-body uploads -- is fetched through
  #     the same integration session that rendered the HTML, so the bytes are
  #     always whatever a visitor's browser would actually receive.
  class StaticExporter
    STATIC_ROOT_FILES = %w[favicon.svg favicon.png app-icon.png app-icon-192.png robots.txt].freeze
    PWA_PATHS = %w[/manifest.json /manifest].freeze

    # Matches asset, upload, and blob URLs *inside a quoted attribute* (src, href,
    # data-lightbox-url-value, or the og:image content=), with an optional
    # absolute host prefix so covers are caught too. Bounding the match to the
    # closing quote keeps the scan from over-running into adjacent HTML when a
    # URL sits in unquoted text; only the path (group 1) is captured.
    RESOURCE_URL_PATTERN = %r{(?:src|href|data-lightbox-url-value|content)\s*=\s*["'](?:https?://[^/]+)?(/(?:assets/[^"']+|u/[^"']+|rails/active_storage/[^"']+))["']}

    # <a> elements pointing at session/user/account or edit paths -- dead links
    # on a static host. Only the library's sign-in button appears in the
    # logged-out read views.
    AUTH_LINK_PATTERN = /<a\s[^>]*href="(?:\/(?:session|users|account)|[^"]*\/edit)[^"]*"[^>]*>.*?<\/a>/m

    # The search dialog's <form id="search_form"> posts to /books/:id/search,
    # a route that exists only in the live app. On a static host it 404s into
    # Turbo's "content missing" fallback. Neutralize the form in the export:
    # drop its action and short-circuit submission (data-turbo="false" makes
    # Turbo ignore the form; onsubmit="return false" cancels the native submit),
    # so the dialog still opens for visual parity but no request ever fires.
    SEARCH_FORM_PATTERN = /<form\s[^>]*\bid="search_form"[^>]*>/.freeze

    # The table-of-contents sidebar embedded in every leaf page. It is
    # byte-identical across every leaf of a book, so it is externalized once
    # per book and loaded with a small inline fetch (see +externalize_sidebar+).
    # No \b word boundaries: a \b immediately after a double quote never
    # matches, since both sides are non-word characters.
    SIDEBAR_ASIDE_PATTERN = /<aside\s[^>]*?id="sidebar"[^>]*>.*?<\/aside>/m

    # The inline script that swaps the placeholder <aside> for the shared
    # sidebar fragment. The fetch target is RELATIVE -- "../../_sidebar.html",
    # resolved against the leaf's own directory -- so the same export works
    # whether it is hosted at the domain root (a downloaded .zip uploaded
    # straight to a static host) or under a subpath (the in-app /static-site
    # preview, a GitHub Pages project site, any /repo/ prefix). A root-relative
    # "/<book_rel>/_sidebar.html" would 404 under every subpath; a bare relative
    # path depends on document.baseURI and 404s one level too shallow when the
    # leaf URL has no trailing slash (the common case -- Turbo serves leaf links
    # without one).
    #
    # The trailing-slash normalization is the crux. Forcing the pathname to end
    # in "/" promotes the final segment from a "file" to a directory, so "../../"
    # then climbs exactly two levels: from <leaf_slug>/ up past <leaf_id>/ to
    # <book_rel>/, where _sidebar.html lives. The built string starts with "/",
    # so fetch resolves it against the origin -- NOT document.baseURI -- which
    # removes the last baseURI dependence and makes the resolution deterministic
    # across slash/no-slash and root/subpath alike.
    #
    # The !r.ok guard stops a 404 response body from being read as text and
    # outerHTML'd into the page (fetch does not reject on 404; the .catch only
    # covers network errors).
    SIDEBAR_PLACEHOLDER = '<aside id="sidebar" aria-label="Table of Contents" data-static-sidebar-placeholder></aside>'

    def sidebar_fetch_script
      <<~JS
        <script>
        (function(){
        var p=location.pathname;
        if(!p.endsWith("/"))p+="/";
        fetch(p+"../../_sidebar.html").then(function(r){
        if(!r.ok)return null;
        return r.text();
        }).then(function(h){
        if(!h)return;
        var s=document.querySelector("aside[data-static-sidebar-placeholder]");
        if(s)s.outerHTML=h;
        }).catch(function(){});
        })();
        </script>
      JS
    end

    Result = Struct.new(:books, :leaves, :assets, :resources, :resource_failures, :bytes, keyword_init: true)

    def initialize(output_dir, host: "example.com", protocol: "https", verbose: false)
      @output_dir = Pathname.new(output_dir)
      @host = host.to_s
      @protocol = protocol.to_s
      @verbose = verbose
      @rendered = [] # Array of [String rel, String html]
      @resource_ok = 0
      @resource_fail = 0
    end

    def call
      configure_url_options
      FileUtils.rm_rf(@output_dir)
      FileUtils.mkdir_p(@output_dir)

      render_library
      mirror_precompiled_assets
      copy_root_files
      copy_resources
      fetch_pwa_manifest

      write_manifest
      Result.new(books: @book_count, leaves: @leaf_count, assets: @asset_count,
                resources: @resource_ok, resource_failures: @resource_fail, bytes: dir_size)
    ensure
      restore_url_options
    end

    private
      def session
        @session ||= begin
          s = ActionDispatch::Integration::Session.new(Rails.application)
          s.host = @host
          s.https! if @protocol == "https"
          s
        end
      end

      def configure_url_options
        @original_url_options = Rails.application.routes.default_url_options.dup
        opts = { host: @host, protocol: @protocol }
        Rails.application.routes.default_url_options.update(opts)
        ActiveStorage::Current.url_options = opts
      end

      def restore_url_options
        Rails.application.routes.default_url_options.clear
        Rails.application.routes.default_url_options.update(@original_url_options) if @original_url_options
      end

      def get(path)
        session.get(path)
        status = session.response.status
        raise "GET #{path} returned #{status}\n#{session.response.body[0, 500]}" unless (200..299).cover?(status)
        session.response.body
      end

      # Fetches the bytes behind a URL, following ActiveStorage's redirects.
      # Returns the final 200 body, or +nil+ on failure. Variants are generated
      # on demand by the request itself.
      def fetch_bytes(url, redirect_limit = 6)
        target = url
        redirect_limit.times do
          session.get(target)
          response = session.response
          return body_bytes(response) if (200..299).cover?(response.status)
          return nil unless (300..399).cover?(response.status) && response.location
          target = URI.parse(response.location).request_uri
        end
      end

      def body_bytes(response)
        body = response.body
        body = Array(body).map(&:to_s).join unless body.is_a?(String)
        body&.bytesize&.positive? ? body : nil
      end

      def write(rel, body, binary: false)
        dest = @output_dir.join(rel)
        FileUtils.mkdir_p(dest.dirname)
        binary ? File.binwrite(dest, body) : File.write(dest, body)
      end

      def render(rel, html)
        html = make_relative(neutralize_search_form(strip_dead_auth_links(html)))
        write(rel, html)
        @rendered << [rel, html]
        html
      end

      def strip_dead_auth_links(html)
        html.gsub(AUTH_LINK_PATTERN, "")
      end

      def neutralize_search_form(html)
        html.gsub(SEARCH_FORM_PATTERN) do |form|
          form = form.sub(/\saction="[^"]*"/, "")
          form = form.sub(/\sdata-turbo="[^"]*"/, "")
          form.sub(/>/, ' data-turbo="false" onsubmit="return false">')
        end
      end

      # Rewrite absolute URLs to the export host as root-relative so the site is
      # self-contained. External URLs (e.g. once.com) are left untouched. The
      # optional port covers the :443 Rails appends under https!.
      def make_relative(html)
        return html if @host.empty?
        html.gsub(%r{https?://#{Regexp.escape(@host)}(?::\d+)?}, "")
      end

      def render_library
        log "Rendering library index"
        # Point each library card's bookmark frame at the static directory's
        # index.html so Turbo loads it without a redirect on the static host
        # (see +render_bookmark+). Only the library index carries these frames.
        library_html = rewrite_bookmark_frame_srcs(get("/"))
        render("index.html", library_html)

        books = Book.published.ordered.to_a
        @book_count = books.size
        @leaf_count = 0

        books.each do |book|
          book_path = "/#{book.id}/#{book.slug}"
          book_rel  = "#{book.id}/#{book.slug}"
          log "Book ##{book.id} #{book.title.inspect} -> #{book_rel}/"
          render("#{book_rel}/index.html", get(book_path))
          # The book and leaf views each declare a <link rel="alternate"
          # type="text/markdown" href="….md"> pointing at the front-matter
          # markdown the app serves via format.md. Render those routes too so
          # the alternate links resolve on a static host instead of 404ing.
          render("#{book_rel}.md", get("#{book_path}.md"))
          render_bookmark(book)

          leaves = book.leaves.active.with_leafables.positioned.to_a
          leaf_htmls = []
          leaves.each_with_index do |leaf, index|
            leaf_rel = "#{book_rel}/#{leaf.id}/#{leaf.slug}"
            html = render("#{leaf_rel}/index.html", get("#{book_path}/#{leaf.id}/#{leaf.slug}"))
            render("#{leaf_rel}.md", get("#{book_path}/#{leaf.id}/#{leaf.slug}.md"))
            leaf_htmls << [ "#{leaf_rel}/index.html", html ]
            @leaf_count += 1
            log "  [#{index + 1}/#{leaves.size}] #{leaf.title.inspect}" if @verbose && (index % 50).zero?
          end

          externalize_sidebar(book_rel, leaf_htmls) unless leaf_htmls.empty?
        end
        log "Rendered #{@book_count} #{'book'.pluralize(@book_count)}, #{@leaf_count} #{'leaf'.pluralize(@leaf_count)}"
      end

      # The library's book cards auto-fetch <tt>/books/:id/bookmark</tt> into a
      # Turbo frame; the response carries the overlay link that turns a card
      # into a click target. Render that route per book so the fetch resolves on
      # a static host instead of 404ing into Turbo's "content missing" fallback.
      # The file is written under <tt>books/:id/</tt> to match the frame's
      # <tt>src="/books/:id/bookmark/"</tt> (the route is keyed on the book id,
      # not its slug), so the static host serves it directly with no redirect.
      def render_bookmark(book)
        html = get("/books/#{book.id}/bookmark")
        render("books/#{book.id}/bookmark/index.html", html)
      end

      # Rewrite the bookmark frame <tt>src="/books/:id/bookmark"</tt> to a
      # trailing slash so the browser hits the directory's index.html directly.
      # The negative lookahead avoids double-slashing an already-rewritten URL.
      def rewrite_bookmark_frame_srcs(html)
        html.gsub(%r{src="/books/(\d+)/bookmark"(?!/)}, 'src="/books/\1/bookmark/"')
      end

      # The leaf sidebar -- the full book table of contents -- is identical in
      # every leaf of a book. Writing it once per book and loading it with a
      # tiny inline fetch turns an O(n^2) export (every leaf carries the whole
      # TOC) into O(n). With JS off the sidebar nav is absent, but the page body
      # and prev/next navigation still work. This is the only JS the exporter
      # adds; everything else is Writebook's own.
      def externalize_sidebar(book_rel, leaf_htmls)
        sidebar = leaf_htmls.first.last[SIDEBAR_ASIDE_PATTERN]
        return unless sidebar

        write("#{book_rel}/_sidebar.html", sidebar)
        log "  externalized sidebar -> #{book_rel}/_sidebar.html (#{sidebar.bytesize} bytes)"

        replacement = SIDEBAR_PLACEHOLDER + "\n" + sidebar_fetch_script
        rendered_index = @rendered.to_h { |rel, html| [rel, html] }

        leaf_htmls.each do |rel, html|
          trimmed = html.sub(SIDEBAR_ASIDE_PATTERN, replacement)
          next if trimmed == html
          write(rel, trimmed)
          rendered_index[rel] = trimmed if rendered_index.key?(rel)
        end

        @rendered = rendered_index.to_a
      end

      def mirror_precompiled_assets
        src = Rails.public_path.join("assets")
        return @asset_count = 0 unless src.directory?
        FileUtils.cp_r(src, @output_dir.join("assets"))
        @asset_count = Dir.glob(@output_dir.join("assets", "**", "*").to_s).count { |p| File.file?(p) }
        log "Mirrored #{@asset_count} precompiled asset files"
      end

      def copy_root_files
        STATIC_ROOT_FILES.each do |file|
          src = Rails.public_path.join(file)
          FileUtils.cp(src, @output_dir.join(file)) if src.exist?
        end
      end

      def copy_resources
        urls = @rendered.flat_map { |_, html| html.scan(RESOURCE_URL_PATTERN).map(&:first) }.uniq
        log "Found #{urls.size} referenced #{'resource'.pluralize(urls.size)}" if @verbose
        urls.each do |url|
          rel = url.sub(/\?.*\z/, "").sub(%r{^/}, "")
          next if @output_dir.join(rel).exist? # already satisfied by the precompiled mirror
          if (bytes = fetch_bytes(url))
            write(rel, bytes, binary: true)
            @resource_ok += 1
          else
            @resource_fail += 1
            log "  could not fetch #{url}"
          end
        end
        log "Fetched #{@resource_ok} #{'resource'.pluralize(@resource_ok)}, #{@resource_fail} failed"
      end

      def fetch_pwa_manifest
        PWA_PATHS.each do |path|
          begin
            write("manifest.json", get(path))
            log "  fetched #{path} -> manifest.json" if @verbose
            return
          rescue => e
            log "  skipped #{path}: #{e.message}" if @verbose
          end
        end
      end

      def write_manifest
        @output_dir.join("_static_export_manifest.txt").write(manifest_text)
      end

      def manifest_text
        <<~MSG
          Writebook static export
          ----------------------
          host:      #{@host}
          books:     #{@book_count}
          leaves:    #{@leaf_count}
          assets:    #{@asset_count}
          resources: #{@resource_ok} (failed: #{@resource_fail})
          size:      #{dir_size}
        MSG
      end

      def dir_size
        `du -sh #{@output_dir}`.strip.split.first
      end

      def log(message)
        puts message if @verbose
      end
  end
end