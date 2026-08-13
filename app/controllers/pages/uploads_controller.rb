class Pages::UploadsController < ApplicationController
  allow_bearer_key_access

  before_action do
    ActiveStorage::Current.url_options = { protocol: request.protocol, host: request.host, port: request.port }
  end

  before_action :set_page, :ensure_editable

  # Same attach-and-render as ActionText::Markdown::UploadsController, but the
  # page comes from the path instead of a signed GlobalID, which no script can mint.
  def create
    @markdown = @page.body
    @markdown.uploads.attach [ params[:file] ]
    @markdown.save!

    @upload = @markdown.uploads.attachments.last

    render "action_text/markdown/uploads/create", status: :created, formats: :json
  end

  private
    def set_page
      @book = Book.accessable_or_published.find(params[:book_id])
      leafable = @book.leaves.active.find(params[:page_id]).leafable

      head :unprocessable_entity unless @page = (leafable if leafable.is_a?(Page))
    end

    def ensure_editable
      head :forbidden unless @book.editable?
    end
end
