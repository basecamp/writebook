class Picture < ApplicationRecord
  include Leafable

  has_one_attached :image do |attachable|
    attachable.variant :large, resize_to_limit: [ 1500, 1500 ]
  end

  def to_markdown
    "#{caption.presence || image&.attachment&.slug || "Image"}"
  end
end
