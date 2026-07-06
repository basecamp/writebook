class StaticExportsController < ApplicationController
  # Generating a static copy of the whole library is a site-wide admin action:
  # it renders every published book and copies every asset and image blob into a
  # directory on the server. Non-admins get 403; logged-out visitors are sent to
  # sign in by the default authentication before_action.
  before_action :ensure_can_administer

  # The landing page: explains what the export produces and offers the button
  # that POSTs to #create to run it.
  def show
  end

  # Renders the published library to tmp/static-site (the same default the
  # static:generate rake task uses) and shows the result with hosting steps.
  # Synchronous -- Writebook runs no background jobs, and a published-only
  # export takes seconds. Operators with very large libraries should use the
  # rake task instead (noted on the result page) to avoid a request timeout.
  def create
    @output_dir = static_dir.expand_path

    # Nothing to render: the library root itself redirects when there are no
    # published books, so short-circuit before the exporter would hit that.
    if Book.published.none?
      render :empty
    else
      @result = generate
      render :create
    end
  end

  # Streams the generated site as a single .zip the operator can download from
  # the browser -- no server shell needed. Reuses the directory #create built;
  # regenerates first if it's absent (e.g. the operator bookmarked this URL).
  def download
    ensure_static_site_generated
    send_file zip_static_site, filename: "writebook-static-site.zip",
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

    def generate
      Writebook::StaticExporter.new(
        static_dir,
        host: request.host,
        protocol: request.ssl? ? "https" : "http"
      ).call
    end

    # Build the static site only when it isn't already on disk, so a direct hit
    # on download/preview still works without redoing the work #create did.
    def ensure_static_site_generated
      generate unless static_dir.join("index.html").exist?
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