module Oauth
  CLIENT_ID = "writebook-cli"
  DEVICE_CODE_GRANT_TYPE = "urn:ietf:params:oauth:grant-type:device_code"
  GRANT_TYPES = [ DEVICE_CODE_GRANT_TYPE, "refresh_token" ].freeze

  def self.table_name_prefix
    "oauth_"
  end
end
