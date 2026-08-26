class Book < ApplicationRecord
  include Accessable, Sluggable

  has_many :leaves, dependent: :destroy
  has_one_attached :cover, dependent: :purge_later

  scope :ordered, -> { order(:title) }
  scope :published, -> { where(published: true) }

  enum :theme, %w[ black blue green magenta orange violet white ].index_by(&:itself), suffix: true, default: :blue

  def press(leafable, leaf_params)
    leaves.create! leaf_params.merge(leafable: leafable)
  end

  def markable
    leaves.active.positioned.map { it.leafable.markable }.join("\n\n")
  end

  def fingerprint
    Digest::SHA256.hexdigest [ title, subtitle, author, theme, cover.attached? ? cover.blob.checksum : nil ].join("\0")
  end
end
