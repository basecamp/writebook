class Oauth::TokensController < Oauth::BaseController
  before_action :require_recognized_client

  def create
    case params[:grant_type]
    when Oauth::DEVICE_CODE_GRANT_TYPE
      redeem_device_code
    when "refresh_token"
      rotate_refresh_token
    else
      raise Oauth::Error.unsupported_grant_type
    end
  end

  private
    def redeem_device_code
      grant = Oauth::DeviceGrant.find_by_raw_device_code(params[:device_code])

      if grant.nil?
        raise Oauth::Error.invalid_grant("Invalid device code")
      end

      grant.judge_poll!
      access_token, refresh_token = grant.redeem!

      render json: token_response(access_token, refresh_token)
    end

    def rotate_refresh_token
      refresh_token = Oauth::RefreshToken.find_presented!(params[:refresh_token])
      successor = refresh_token.rotate!

      render json: token_response(successor.issue_access_token!, successor)
    end

    def token_response(access_token, refresh_token)
      {
        access_token: access_token.raw_token,
        token_type: "Bearer",
        expires_in: Oauth::AccessToken::EXPIRES_IN.to_i,
        refresh_token: refresh_token.raw_token
      }
    end
end
