# RFC 8628 §3.1-3.2: a CLI requests a device code and user code pair here,
# displays the user code, and polls the token endpoint while the user
# approves at the verification URL.
class Oauth::DeviceAuthorizationsController < Oauth::BaseController
  before_action :require_recognized_client

  def create
    grant = Oauth::DeviceGrant.generate!

    render json: {
      device_code: grant.raw_device_code,
      user_code: grant.formatted_user_code,
      verification_uri: oauth_device_verification_url,
      verification_uri_complete: oauth_device_verification_url(user_code: grant.formatted_user_code),
      expires_in: Oauth::DeviceGrant::EXPIRES_IN.to_i,
      interval: Oauth::DeviceGrant::POLLING_INTERVAL.to_i
    }
  end
end
