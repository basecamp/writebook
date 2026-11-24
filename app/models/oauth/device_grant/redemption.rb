# Token-endpoint redemption of a device grant: RFC 8628 poll judgment,
# atomic consumption, and token minting.
module Oauth::DeviceGrant::Redemption
  # Judge a token-endpoint poll, raising in RFC 8628 §3.5 order. Returns
  # quietly only when the grant is approved and ready to redeem.
  #
  # A request carrying the approval code the user was shown isn't a poll: it
  # needs no interval, and it succeeds only once that code matches. Guessing
  # it gains nothing, since whoever holds the device code could just poll.
  def judge_poll!(approval_code: nil)
    if expired?
      raise Oauth::Error.expired_token
    end

    if approval_code.present?
      judge_approval_code!(approval_code)
      return
    end

    if polled_too_fast?
      record_poll
      raise Oauth::Error.slow_down
    end

    record_poll

    if denied?
      raise Oauth::Error.access_denied("The user denied the authorization request")
    end

    if pending?
      raise Oauth::Error.authorization_pending
    end
  end

  def redeem!
    transaction do
      unless consume!
        raise Oauth::Error.invalid_grant("Device code has already been used")
      end

      refresh_token = Oauth::RefreshToken.generate!(user: user)
      [ refresh_token.issue_access_token!, refresh_token ]
    end
  end

  private
    def judge_approval_code!(approval_code)
      if denied?
        raise Oauth::Error.access_denied("The user denied the authorization request")
      end

      unless approved? && approval_code_matches?(approval_code)
        raise Oauth::Error.invalid_grant("That approval code doesn't match. Check the code Writebook showed and try again")
      end
    end

    # UPDATE WHERE consumed_at IS NULL, so a device code can never be
    # redeemed twice.
    def consume!
      self.class.where(id: id, consumed_at: nil, status: "approved")
        .update_all(consumed_at: Time.current) == 1
    end

    def polled_too_fast?
      last_polled_at.present? && last_polled_at > Oauth::DeviceGrant::POLLING_INTERVAL.ago
    end

    def record_poll
      update_column :last_polled_at, Time.current
    end
end
