class ActionText::Markdown::UploadsController < ApplicationController
  allow_unauthenticated_access only: :show

  before_action do
    ActiveStorage::Current.url_options = { protocol: request.protocol, host: request.host, port: request.port }
  end

  before_action :set_record, :ensure_editable, only: :create
  before_action :set_attachment, :ensure_attachment_readable, only: :show

  def create
    @markdown = @record.safe_markdown_attribute params[:attribute_name]
    @markdown.uploads.attach [ params[:file] ]
    @markdown.save!

    @upload = @markdown.uploads.attachments.last

    render :create, status: :created, formats: :json
  end

  def show
    if @book&.published?
      expires_in 1.year, public: true
    else
      expires_in 5.minutes, public: false
    end

    redirect_to @attachment.url
  end

  private
    # The signed id rendered into the page editor says who could upload when it was
    # minted, not who may upload now. Resolve the book it belongs to and authorize
    # against that, so revoking access takes effect here like it does everywhere else.
    def set_record
      @record = GlobalID::Locator.locate_signed params[:record_gid],
        only: Page, for: ActionText::Markdown::UPLOADS_SIGNED_ID_PURPOSE
      @book = Book.accessable_or_published.find_by(id: @record&.owning_book&.id)

      head :not_found unless @book
    end

    def ensure_editable
      head :forbidden unless @book.editable?
    end

    def set_attachment
      @attachment = ActiveStorage::Attachment.find_by! slug: "#{params[:slug]}.#{params[:format]}"
      @book = @attachment.record.try(:record).try(:owning_book)
    end

    # An unpublished book's uploads are as private as the book itself. Serving them to
    # anyone holding the URL made this a way to read them without an access row, and
    # caching them publicly for a year put them in shared caches besides. An attachment
    # whose owning book can't be resolved has no book to authorize against, so fail
    # closed rather than letting the nil short-circuit the check.
    def ensure_attachment_readable
      head :not_found unless @book&.published? || @book&.accessable?
    end
end
