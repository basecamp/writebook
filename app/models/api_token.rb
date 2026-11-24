# A long-lived, read-only token for scripts and agents that can't take part in
# the browser approval of the OAuth device flow. It reads what its user can
# read and nothing more: it only authenticates GET requests, and only on the
# actions that opt in with `allow_api_token_access` (books, pages, manifests,
# search). Everything else answers 403. It reads text: uploads and images in
# private books still need a browser session or an OAuth access token. Revoke
# one by deleting it.
class ApiToken < ApplicationRecord
  ACTIVITY_REFRESH_RATE = 1.hour

  belongs_to :user

  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true

  scope :ordered, -> { order(created_at: :desc) }

  attr_accessor :raw_token

  PREFIX = Oauth::TokenGenerator::PREFIXES.fetch(:api_token)

  class << self
    def generate!(name:)
      raw_token = Oauth::TokenGenerator.api_token

      create!(name: name, token_digest: Oauth::TokenDigester.digest(raw_token))
        .tap { it.raw_token = raw_token }
    end

    def find_by_raw_token(raw_token)
      if raw_token.is_a?(String) && raw_token.start_with?(PREFIX)
        joins(:user).merge(User.active).find_by token_digest: Oauth::TokenDigester.digest(raw_token)
      end
    end
  end

  def record_use
    if last_used_at.nil? || last_used_at.before?(ACTIVITY_REFRESH_RATE.ago)
      update_column :last_used_at, Time.current
    end
  end
end
