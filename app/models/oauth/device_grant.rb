# RFC 8628 Device Authorization Grant. A CLI requests a device code and user
# code pair, shows the user code, and polls the token endpoint while the user
# approves the code at the verification URL in any signed-in browser.
#
# Device codes are stored as digests. User codes are stored plaintext (they
# must be looked up by user input) and are protected by rate limiting, a short
# TTL, and an unambiguous 8-character alphabet.
class Oauth::DeviceGrant < ApplicationRecord
  include Redemption

  EXPIRES_IN = 10.minutes
  POLLING_INTERVAL = 5.seconds

  USER_CODE_ALPHABET = ("A".."Z").to_a + ("2".."9").to_a - %w[ O I L ]
  USER_CODE_LENGTH = 8

  belongs_to :user, optional: true

  validates :device_code_digest, presence: true, uniqueness: true
  validates :user_code, presence: true, uniqueness: true
  validates :status, inclusion: { in: %w[ pending approved denied ] }
  validates :user, presence: true, if: :approved?

  attr_accessor :raw_device_code

  class << self
    def generate!
      raw_device_code = Oauth::TokenGenerator.device_code

      create!(device_code_digest: Oauth::TokenDigester.digest(raw_device_code),
        user_code: generate_user_code, expires_at: EXPIRES_IN.from_now)
          .tap { it.raw_device_code = raw_device_code }
    end

    def find_by_raw_device_code(raw_device_code)
      if raw_device_code.is_a?(String) && raw_device_code.present?
        find_by device_code_digest: Oauth::TokenDigester.digest(raw_device_code)
      end
    end

    def find_pending_by_user_code(user_code)
      if user_code.is_a?(String) && user_code.present?
        where(status: "pending").where("expires_at > ?", Time.current)
          .find_by(user_code: user_code.strip.delete("-").upcase)
      end
    end

    private
      def generate_user_code
        USER_CODE_LENGTH.times.map { USER_CODE_ALPHABET[SecureRandom.random_number(USER_CODE_ALPHABET.size)] }.join
      end
  end

  # Atomic UPDATE WHERE, so a raced approval or denial can't overwrite the
  # transition that got there first.
  def approve!(user)
    self.class.where(id: id, status: "pending")
      .update_all(status: "approved", user_id: user.id, updated_at: Time.current) == 1
  end

  def deny!
    self.class.where(id: id, status: "pending")
      .update_all(status: "denied", updated_at: Time.current) == 1
  end

  def expired?
    expires_at < Time.current
  end

  def pending?
    status == "pending"
  end

  def approved?
    status == "approved"
  end

  def denied?
    status == "denied"
  end

  def formatted_user_code
    "#{user_code[0..3]}-#{user_code[4..7]}"
  end
end
