# Tokens are never stored in plain text. We store HMAC-SHA256(pepper, raw_token),
# which allows lookup by raw token while preventing token extraction from a
# database leak. The pepper derives from secret_key_base, so rotating that
# invalidates every outstanding token.
module Oauth::TokenDigester
  extend self

  def digest(raw_token)
    OpenSSL::HMAC.hexdigest("SHA256", pepper, raw_token)
  end

  private
    def pepper
      @pepper ||= Rails.application.key_generator.generate_key("oauth/token_digester")
    end
end
