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

  def to_markdown(url_options: ActiveStorage::Current.url_options)
    [ "# #{title}", leaves.active.with_leafables.positioned.map { |leaf| leaf.to_markdown(url_options: url_options) } ]
      .flatten
      .reject(&:blank?)
      .join("\n\n")
  end
end
