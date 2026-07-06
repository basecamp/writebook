class StaticExportsController < ApplicationController
  # Generating a static copy of the library -- the whole thing or a single book
  # -- is a site-wide admin action: it renders books and copies every asset and
  # image blob they reference into a directory on the server. Non-admins get 403;
  # logged-out visitors are sent to sign in by the default authentication
  # before_action.
  before_action :ensure_can_administer

  # The landing page: explains what the export produces and offers the form
  # that POSTs to #create to run it. The form lets the operator pick "all
  # published books" (optionally with unpublished drafts) or a single book to
  # export by itself, so @books (every book, published or not) is loaded for the
  # selector -- a draft can be exported individually even though it isn't
  # published.
  def show
    @books = Book.ordered.to_a
  end

  # Renders the library to tmp/static-site (the same default the
  # static:generate rake task uses) and redirects to #result, which shows the
  # result with hosting steps. Two scopes, both rolled back so the live database
  # is untouched:
  #
  #   * Pass book_id=<id> to export a single book by itself, regardless of its
  #     published state. The library menu in the result shows just that book.
  #   * Otherwise export every published book. Pass include_drafts=1 to also
  #     include unpublished books.
  #
  # Synchronous -- a published-only export takes seconds; operators with very
  # large libraries should use the rake task instead (noted on the landing page)
  # to avoid a request timeout.
  #
  # The redirect (PRG) is required because the landing form is Turbo-driven:
  # a Turbo form submission must receive a 3xx redirect. A 200 HTML response
  # (the former `render :create`) makes Turbo throw "Form responses must
  # redirect to another location". The result is stashed in the session and
  # rendered by the GET #result action, so the URL is also refresh-safe.
  def create
    book = Book.find_by(id: params[:book_id].presence)

    if book
      result = generate(book: book)
      result.book_id = book.id
      result.book_title = book.title
      session[:static_export_result] = result.to_h.transform_keys(&:to_s)
    else
      include_drafts = params[:include_drafts] == "1"
      # Nothing to render: the library root itself redirects when there are no
      # published books, so short-circuit before the exporter would hit that.
      # (With drafts requested, an empty library -- no books at all -- is the
      # same. A bogus book_id also lands here, falling back to "nothing to
      # export" rather than 500ing.)
      if include_drafts ? Book.none? : Book.published.none?
        session[:static_export_result] = { "empty" => true }
      else
        result = generate(include_drafts: include_drafts)
        session[:static_export_result] = result.to_h.transform_keys(&:to_s)
      end
    end

    redirect_to static_export_result_url, status: :see_other
  end

  # GET: renders the result page stashed by #create. Refresh-safe -- the URL
  # stays valid until another export overwrites the session slot. A direct hit
  # with no stashed result (e.g. the session expired) falls back to the
  # landing page so the operator is never left on a dead URL.
  def result
    data = session[:static_export_result]
    if data.blank?
      redirect_to static_export_url, status: :see_other
      return
    end

    session.delete(:static_export_result)
    @output_dir = static_dir.expand_path
    if data["empty"]
      render :empty
    else
      @result = Writebook::StaticExporter::Result.new(**data.symbolize_keys)
      render :create
    end
  end

  # Streams the generated site as a single .zip the operator can download from
  # the browser -- no server shell needed. Reuses the directory #create built;
  # regenerates first if it's absent (e.g. the operator bookmarked this URL).
  # A book_id query param (carried from the result page's download link when a
  # single book was exported) names the .zip after the book and scopes a
  # regeneration to just that book; without it the whole library is exported.
  def download
    book = Book.find_by(id: params[:book_id].presence)
    ensure_static_site_generated(book: book)
    filename = book ? "writebook-#{book.slug}.zip" : "writebook-static-site.zip"
    send_file zip_static_site, filename: filename,
               type: "application/zip", disposition: "attachment"
  end

  # Serves the generated site from inside the running app so the operator can
  # see the export rendered in a browser tab without a server shell or a
  # separate web server. The directory is mapped under /static-site/ and any
  # path traversal is rejected.
  #
  # The static HTML uses root-relative URLs (/assets/..., /u/..., /rails/...).
  # Those resolve against the live app when the preview is served from a
  # subpath -- which is what we want, since the live app serves the same
  # precompiled assets and the same image blobs the export copied. The relative
  # sidebar fetch (../../_sidebar.html) and per-book files resolve within
  # /static-site/ and are served from the directory. The header CSP is cleared
  # so the static HTML's own <meta> policy governs, just like a real static host.
  def preview
    ensure_static_site_generated
    serve_preview_file
  end

  private
    def static_dir
      Rails.root.join("tmp/static-site")
    end

    # Runs the exporter. The work is done in a separate thread wrapped in the
    # Rails executor: the exporter renders every page through a nested
    # ActionDispatch::Integration::Session, which re-enters the middleware
    # stack and resets ActiveSupport::CurrentAttributes. Running that nested
    # session inside the live request's thread would wipe the request's own
    # Current (and break the layout's `signed_in?`), so it runs in a thread
    # with its own CurrentAttributes scope instead. The thread is joined so the
    # request still returns the result synchronously.
    #
    # Two scopes, both inside a rolled-back transaction so the live database is
    # untouched:
    #
    #   * Pass a +book+ to export just that book: it's temporarily made the only
    #     published book, so the exporter (which reads `Book.published` and the
    #     library `/` route) renders the library menu and the book by itself,
    #     regardless of the book's real published state.
    #   * Otherwise, when +include_drafts+ is set, unpublished books are
    #     temporarily published so the exporter renders them -- the same
    #     approach as `bin/rails static:generate STATIC_ALL=1`.
    def generate(book: nil, include_drafts: false)
      host = request.host
      protocol = request.ssl? ? "https" : "http"
      exporter = -> { Writebook::StaticExporter.new(static_dir, host: host, protocol: protocol).call }

      result = nil
      Thread.new do
        Rails.application.executor.wrap do
          if book
            Book.transaction do
              Book.where.not(id: book.id).update_all(published: false)
              book.update_columns(published: true)
              result = exporter.call
              raise ActiveRecord::Rollback
            end
          elsif include_drafts
            Book.transaction do
              Book.where(published: [false, nil]).update_all(published: true)
              result = exporter.call
              raise ActiveRecord::Rollback
            end
          else
            result = exporter.call
          end
        end
      end.join
      result
    end

    # Build the static site only when it isn't already on disk, so a direct hit
    # on download/preview still works without redoing the work #create did. When
    # a +book+ is given (a bookmarked single-book download URL), a regeneration
    # is scoped to just that book instead of the whole library.
    def ensure_static_site_generated(book: nil)
      generate(book: book) unless static_dir.join("index.html").exist?
    end

    def zip_static_site
      require "zip"

      zip_path = Rails.root.join("tmp/writebook-static-site.zip")
      FileUtils.rm_f(zip_path)
      root = static_dir

      Zip::File.open(zip_path, Zip::File::CREATE) do |zip|
        Dir.glob(root.join("**", "*").to_s).each do |abs|
          next if File.directory?(abs)
          rel = Pathname.new(abs).relative_path_from(root).to_s
          zip.add("static-site/#{rel}", abs)
        end
      end

      zip_path
    end

    def serve_preview_file
      rel = params[:path].presence || "index.html"
      raise ActionController::RoutingError, "not found" if rel.include?("..") || rel.start_with?("/")

      file = static_dir.join(rel)
      file = file.join("index.html") if file.directory?

      root = static_dir.expand_path.to_s
      unless file.file? && File.expand_path(file.to_s).start_with?("#{root}/")
        raise ActionController::RoutingError, "not found"
      end

      response.headers["Content-Security-Policy"] = nil
      send_file file.to_s, disposition: "inline"
    end
end