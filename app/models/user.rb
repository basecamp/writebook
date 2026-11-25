class User < ApplicationRecord
  include Role, Transferable

  has_many :sessions, dependent: :destroy
  has_many :api_tokens, dependent: :destroy
  has_secure_password validations: false

  has_many :accesses, dependent: :destroy
  has_many :books, through: :accesses
  has_many :leaves, through: :books

  validates :name, :email_address, presence: true
  validates :password, presence: true, if: -> { new_record? || password_digest_changed? }

  after_create :grant_access_to_everyone_books

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:name) }

  def current?
    self == Current.user
  end

  def editor_of?(book)
    can_administer? || editor_book_ids.include?(book.id)
  end

  def deactivate
    transaction do
      sessions.delete_all
      api_tokens.delete_all
      update! active: false, email_address: deactived_email_address
    end
  end

  private
    def editor_book_ids
      @editor_book_ids ||= accesses.editor.pluck(:book_id).to_set
    end

    def deactived_email_address
      email_address&.gsub(/@/, "-deactivated-#{SecureRandom.uuid}@")
    end

    def grant_access_to_everyone_books
      all_accesses = Book.with_everyone_access.ids.collect { |id| { book_id: id, level: :reader } }
      accesses.insert_all(all_accesses)
    end
end
