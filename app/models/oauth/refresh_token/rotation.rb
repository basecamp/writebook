# Refresh-token rotation (OAuth 2.1 §6.1): every refresh mints a successor
# and retires its predecessor atomically, with a bounded grace window for
# idempotent retries and family revocation as the theft response.
module Oauth::RefreshToken::Rotation
  extend ActiveSupport::Concern

  REPLAY_GRACE = 1.minute

  # Four outcomes:
  # - A fresh rotation mints and links a new successor.
  # - A grace-window replay is an idempotent retry: return the successor the
  #   first rotation minted, so a client that lost the response doesn't get
  #   revoked as a thief.
  # - Reuse outside the grace window is a theft signal: kill the family.
  # - A lost rotation race reloads and serves the winner's successor via the
  #   same grace path.
  def rotate!
    if rotated?
      if within_grace_window?
        successor_for_retry!
      else
        revoke_family
        raise Oauth::Error.invalid_grant("Token reuse detected, session terminated")
      end
    else
      rotate_freshly!
    end
  end

  private
    def rotate_freshly!
      successor = self.class.generate!(user: user, family_id: family_id)

      if rotate_to?(successor)
        successor
      else
        reload

        if within_grace_window?
          successor_for_retry!
        else
          raise Oauth::Error.invalid_grant("Token rotation conflict")
        end
      end
    end

    # UPDATE WHERE rotated_at IS NULL, so concurrent refreshes can't fork
    # the family. The successor's raw token is stored encrypted for grace
    # window retries; the race loser destroys its speculative successor.
    def rotate_to?(successor)
      rotated = self.class.where(id: id, rotated_at: nil, revoked_at: nil).update_all(
        rotated_at: Time.current,
        replaced_by_id: successor.id,
        successor_raw_token: encryptor.encrypt_and_sign(successor.raw_token)) == 1

      if rotated
        reload
        true
      else
        successor.destroy
        false
      end
    end

    def within_grace_window?
      rotated? && rotated_at > REPLAY_GRACE.ago
    end

    def successor_for_retry!
      successor = replaced_by

      # Once the successor has itself been rotated, the client demonstrably
      # received it and moved on — serving it again would talk the client
      # backwards onto a spent credential.
      if successor.nil? || successor.rotated?
        raise Oauth::Error.invalid_grant("Refresh token superseded")
      end

      successor.raw_token = decrypted_successor_raw_token

      if successor.raw_token.nil?
        raise Oauth::Error.invalid_grant("Grace window token not available")
      end

      successor
    end

    def decrypted_successor_raw_token
      if successor_raw_token.present?
        encryptor.decrypt_and_verify(successor_raw_token)
      end
    rescue ActiveSupport::MessageEncryptor::InvalidMessage
      nil
    end

    def encryptor
      @encryptor ||= ActiveSupport::MessageEncryptor.new \
        Rails.application.key_generator.generate_key("oauth/refresh_token_successor", 32)
    end
end
