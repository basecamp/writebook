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
    dir = Rails.root.join("tmp/static-site")
    @result = Writebook::StaticExporter.new(
      dir,
      host: request.host,
      protocol: request.ssl? ? "https" : "http"
    ).call
    @output_dir = dir

    render :create
  end
end