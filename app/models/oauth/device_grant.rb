# RFC 8628 Device Authorization Grant. A CLI requests a device code and user
# code pair, shows the user code, and polls the token endpoint while the user
# approves the code at the verification URL in any signed-in browser.
#
# Device codes are stored as digests. User codes are stored plaintext (they
# must be looked up by user input) and are protected by rate limiting, a short
# TTL, and an unambiguous 8-character alphabet.
#
# Approving also shows the user an approval code, stored as a digest. Typing
# it into the CLI finishes sign-in right away, so a CLI on a machine with no
# browser (or one that can't wait and poll) works too: it prints the link,
# the user approves anywhere, and enters the code they're shown.
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

  attr_accessor :raw_device_code, :raw_approval_code

  class << self
    def generate!
      raw_device_code = Oauth::TokenGenerator.device_code

      create!(device_code_digest: Oauth::TokenDigester.digest(raw_device_code),
        user_code: generate_code, expires_at: EXPIRES_IN.from_now)
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
          .find_by(user_code: normalize_code(user_code))
      end
    end

    def generate_code
      USER_CODE_LENGTH.times.map { USER_CODE_ALPHABET[SecureRandom.random_number(USER_CODE_ALPHABET.size)] }.join
    end

    def format_code(code)
      "#{code[0..3]}-#{code[4..7]}"
    end

    def normalize_code(code)
      code.to_s.strip.delete("-").upcase
    end
  end

  # Atomic UPDATE WHERE, so a raced approval or denial can't overwrite the
  # transition that got there first.
  def approve!(user)
    raw_approval_code = self.class.generate_code

    approved = self.class.where(id: id, status: "pending").update_all(status: "approved", user_id: user.id,
      approval_code_digest: Oauth::TokenDigester.digest(raw_approval_code), updated_at: Time.current) == 1

    self.raw_approval_code = raw_approval_code if approved
    approved
  end

  def approval_code_matches?(code)
    approval_code_digest.present? &&
      ActiveSupport::SecurityUtils.secure_compare(approval_code_digest, Oauth::TokenDigester.digest(self.class.normalize_code(code)))
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
    self.class.format_code(user_code)
  end

  def formatted_approval_code
    self.class.format_code(raw_approval_code) if raw_approval_code
  end
end
