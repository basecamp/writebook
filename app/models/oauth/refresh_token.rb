# Long-lived tokens used to obtain new access tokens, rotated on every use.
# Tokens minted from one another share a family_id, so detected theft can
# revoke the whole lineage at once.
class Oauth::RefreshToken < ApplicationRecord
  include Rotation

  EXPIRES_IN = 90.days

  belongs_to :user
  belongs_to :replaced_by, class_name: "Oauth::RefreshToken", optional: true
  has_many :access_tokens, class_name: "Oauth::AccessToken", dependent: :destroy

  validates :token_digest, presence: true, uniqueness: true
  validates :family_id, presence: true

  attr_accessor :raw_token

  class << self
    def generate!(user:, family_id: nil)
      raw_token = Oauth::TokenGenerator.refresh_token

      create!(user: user, family_id: family_id || SecureRandom.uuid,
        token_digest: Oauth::TokenDigester.digest(raw_token), expires_at: EXPIRES_IN.from_now)
          .tap { it.raw_token = raw_token }
    end

    def find_by_raw_token(raw_token)
      if raw_token.is_a?(String) && raw_token.present?
        find_by token_digest: Oauth::TokenDigester.digest(raw_token)
      end
    end

    # Look up a token presented to the token endpoint and verify it, in
    # order: unknown token, expiry, revocation. A rotated token that has
    # since expired still reaches rotate!'s reuse adjudication — presenting
    # it is the same theft signal as presenting it fresh, and must revoke
    # the family rather than answer as a mere expiry.
    def find_presented!(raw_token)
      refresh_token = find_by_raw_token(raw_token)

      if refresh_token.nil?
        raise Oauth::Error.invalid_grant("Invalid refresh token")
      end

      if refresh_token.expired? && !refresh_token.rotated?
        raise Oauth::Error.invalid_grant("Token has expired")
      end

      if refresh_token.revoked?
        raise Oauth::Error.invalid_grant("Token has been revoked")
      end

      refresh_token
    end
  end

  def issue_access_token!
    Oauth::AccessToken.generate! user: user, refresh_token: self
  end

  def expired?
    expires_at < Time.current
  end

  def revoked?
    revoked_at.present?
  end

  def rotated?
    rotated_at.present?
  end

  def revoke_family
    self.class.where(family_id: family_id, revoked_at: nil).update_all(revoked_at: Time.current)

    Oauth::AccessToken.joins(:refresh_token)
      .where(oauth_refresh_tokens: { family_id: family_id })
      .where(revoked_at: nil)
      .update_all(revoked_at: Time.current)
  end
end
