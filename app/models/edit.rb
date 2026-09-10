class Edit < ApplicationRecord
  belongs_to :leaf
  delegated_type :leafable, types: Leafable::TYPES

  enum :action, %w[ revision trash ].index_by(&:itself)

  after_destroy :destroy_superseded_leafable, if: :revision?

  scope :sorted, -> { order(created_at: :desc) }
  scope :before, ->(edit) { where("created_at < ?", edit.created_at) }
  scope :after, ->(edit) { where("created_at > ?", edit.created_at) }

  def previous
    leaf.edits.before(self).last
  end

  def next
    leaf.edits.after(self).first
  end

  private
    # A revision holds the leafable it superseded, which nothing else references. A trash
    # edit shares the leaf's current leafable, and that one is the leaf's to destroy.
    def destroy_superseded_leafable
      leafable&.destroy
    end
end
