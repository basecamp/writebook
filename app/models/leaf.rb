class Leaf < ApplicationRecord
  include Editable, Positionable, Searchable

  belongs_to :book, touch: true
  delegated_type :leafable, types: Leafable::TYPES, dependent: :destroy
  positioned_within :book, association: :leaves, filter: :active

  delegate :searchable_content, to: :leafable

  enum :status, %w[ active trashed ].index_by(&:itself), default: :active

  scope :with_leafables, -> { includes(:leafable) }

  def slug
    title.parameterize.presence || "-"
  end

  # A content-derived identity for sync clients: comparing fingerprints tells
  # them whether a leaf changed, and sending one back lets the server refuse
  # a write based on a stale copy.
  def fingerprint
    Digest::SHA256.hexdigest "#{title}\0#{leafable.fingerprintable_content}"
  end
end
