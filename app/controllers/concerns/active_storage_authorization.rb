module ActiveStorageAuthorization
  extend ActiveSupport::Concern
  include Authentication::SessionLookup, Authentication::TokenLookup

  private
    # A blob is as readable as the book it belongs to. Resolve that book on every
    # request, so unpublishing a book or revoking a reader takes effect on URLs that
    # were handed out before, the way it does for the book's text. A blob with no
    # book to authorize against fails closed.
    def require_readable_blob
      head :not_found unless readable?(blob_for_authorization)
    end

    def blob_for_authorization
      @blob
    end

    def readable?(blob)
      blob.present? && owning_books_of(blob).any? { it.published? || it.accessable?(user: reader) }
    end

    # A browser session, or the OAuth access token the CLI signs in with, so a
    # checkout can download the cover and images of a private book. Read-only
    # API tokens read text only and open no images.
    def reader
      if bearer_token.present?
        find_access_token_by_header&.user
      else
        find_session_by_cookie&.user
      end
    end

    def owning_books_of(blob)
      ActiveStorage::Attachment.where(blob: blob).flat_map do |attachment|
        case record = attachment.record
        when ActiveStorage::VariantRecord then owning_books_of(record.blob)
        when Book then record
        when ActionText::Markdown then record.record.try(:owning_book)
        else record.try(:owning_book)
        end
      end.compact
    end
end
