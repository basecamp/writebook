class Picture < ApplicationRecord
  include Leafable

  has_one_attached :image do |attachable|
    attachable.variant :large, resize_to_limit: [ 1500, 1500 ]
  end

  def large_image
    image.variable? ? image.variant(:large) : image
  end

  def markable
    caption
  end
end
