# Tokens carry a prefix for quick identification in logs and error reports
# without exposing their contents.
module Oauth::TokenGenerator
  extend self

  PREFIXES = {
    access_token: "wb_at_",
    refresh_token: "wb_rt_",
    device_code: "wb_dc_"
  }.freeze

  TOKEN_BYTES = 32

  def access_token
    generate :access_token
  end

  def refresh_token
    generate :refresh_token
  end

  def device_code
    generate :device_code
  end

  private
    def generate(type)
      "#{PREFIXES.fetch(type)}#{SecureRandom.hex(TOKEN_BYTES)}"
    end
end
