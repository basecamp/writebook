class Oauth::AccessToken < ApplicationRecord
  EXPIRES_IN = 1.hour
  ACTIVITY_REFRESH_RATE = 1.hour

  belongs_to :user
  belongs_to :refresh_token, class_name: "Oauth::RefreshToken", optional: true

  validates :token_digest, presence: true, uniqueness: true

  scope :active, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }

  attr_accessor :raw_token

  class << self
    def generate!(user:, refresh_token: nil)
      raw_token = Oauth::TokenGenerator.access_token

      create!(user: user, refresh_token: refresh_token,
        token_digest: Oauth::TokenDigester.digest(raw_token), expires_at: EXPIRES_IN.from_now)
          .tap { it.raw_token = raw_token }
    end

    def find_by_raw_token(raw_token)
      if raw_token.is_a?(String) && raw_token.present?
        find_by token_digest: Oauth::TokenDigester.digest(raw_token)
      end
    end

    def find_active_by_raw_token(raw_token)
      if token = find_by_raw_token(raw_token)
        token if token.active?
      end
    end
  end

  def active?
    !expired? && !revoked?
  end

  def expired?
    expires_at < Time.current
  end

  def revoked?
    revoked_at.present?
  end

  def revoke
    update! revoked_at: Time.current unless revoked?
  end

  def record_use
    if last_used_at.nil? || last_used_at.before?(ACTIVITY_REFRESH_RATE.ago)
      update_column :last_used_at, Time.current
    end
  end
end
