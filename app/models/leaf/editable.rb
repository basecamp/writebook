module Leaf::Editable
  extend ActiveSupport::Concern

  MINIMUM_TIME_BETWEEN_VERSIONS = 10.minutes

  included do
    has_many :edits, dependent: :delete_all

    after_update :record_moved_to_trash, if: :was_trashed?
  end

  def edit(leafable_params: {}, leaf_params: {})
    if record_new_edit?(leafable_params)
      update_and_record_edit leaf_params, leafable_params
    else
      update_without_recording_edit leaf_params, leafable_params
    end
  end

  private
    def record_new_edit?(leafable_params)
      will_change_leafable?(leafable_params) && last_edit_old?
    end

    def last_edit_old?
      edits.empty? || edits.last.created_at.before?(MINIMUM_TIME_BETWEEN_VERSIONS.ago)
    end

    def will_change_leafable?(leafable_params)
      leafable_params.select do |key, value|
        # Markdown attributes live in an association, not a column, so attributes[] can't see them
        if markdown = leafable.safe_markdown_attribute(key)
          markdown.content.to_s != value.to_s
        else
          leafable.attributes[key.to_s] != value
        end
      end.present?
    end

    def update_without_recording_edit(leaf_params, leafable_params)
      transaction do
        leafable.update!(leafable_params)

        edits.last&.touch
        update! leaf_params
      end
    end

    def update_and_record_edit(leaf_params, leafable_params)
      transaction do
        new_leafable = dup_leafable_with_attachments leafable
        new_leafable.update!(leafable_params)

        edits.revision.create!(leafable: leafable)
        update! leaf_params.merge(leafable: new_leafable)
      end
    end

    def dup_leafable_with_attachments(leafable)
      leafable.dup.tap do |new|
        leafable.attachment_reflections.each do |name, _|
          new.send(name).attach(leafable.send(name).blob)
        end
      end
    end

    def record_moved_to_trash
      edits.trash.create!(leafable: leafable)
    end

    def was_trashed?
      trashed? && previous_changes.include?(:status)
    end
end
