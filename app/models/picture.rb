class Picture < ApplicationRecord
  include Leafable

  has_one_attached :image do |attachable|
    attachable.variant :large, resize_to_limit: [ 1500, 1500 ]
  end

  def to_markdown(title:, url_options: ActiveStorage::Current.url_options)
    [ "### #{title}", image_markdown(url_options), caption.presence ].compact.join("\n\n")
  end

  private
    def image_markdown(url_options)
      return unless image.attached?

      url = Rails.application.routes.url_helpers.rails_blob_url(image, **url_options)
      "![#{title}](#{url})"
    end
end
