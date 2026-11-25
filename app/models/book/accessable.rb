module Book::Accessable
  extend ActiveSupport::Concern

  included do
    has_many :accesses, dependent: :destroy
    scope :with_everyone_access, -> { where(everyone_access: true) }
  end

  class_methods do
    def accessable_or_published(user: Current.user)
      if user.present?
        accessable_or_published_books
      else
        published
      end
    end

    def accessable_or_published_books(user: Current.user)
      user.books.or(published).distinct
    end
  end

  def accessable?(user: Current.user)
    accesses.exists?(user: user)
  end

  def editable?(user: Current.user)
    access_for(user: user)&.editor? || user&.administrator?
  end

  def access_for(user: Current.user)
    accesses.find_by(user: user)
  end

  def role_for(user)
    if user.can_administer?
      "editor"
    else
      accesses.detect { it.user_id == user.id }&.level || "none"
    end
  end

  # Editors and readers replace the whole access list, so they're only taken
  # together. Without them, accesses follow a change to everyone access.
  def update_with_access(attributes, editors: nil, readers: nil)
    if editors.nil? != readers.nil?
      errors.add :base, "Editors and readers must be given together"
      false
    elsif update(attributes)
      if editors
        update_access(editors: editors, readers: readers)
      elsif everyone_access_previously_changed?
        resync_access
      end

      true
    else
      false
    end
  end

  def update_access(editors:, readers:)
    editors = Set.new(editors)
    readers = Set.new(everyone_access? ? User.active.ids : readers)

    all = editors + readers
    all_accesses = all.collect { |user_id|
      { user_id: user_id, level: editors.include?(user_id) ? :editor : :reader }
    }

    accesses.upsert_all(all_accesses, unique_by: [ :book_id, :user_id ])
    accesses.where.not(user_id: all).delete_all
  end

  private
    def resync_access
      update_access(editors: accesses.editor.pluck(:user_id), readers: accesses.pluck(:user_id))
    end
end
