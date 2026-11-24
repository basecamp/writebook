# RFC 7009: revoke a token the client no longer needs. Revoking a refresh
# token revokes its whole family. Always answers 200 — whether the token
# existed is not the caller's business.
class Oauth::RevocationsController < Oauth::BaseController
  before_action :require_recognized_client

  def create
    if refresh_token = Oauth::RefreshToken.find_by_raw_token(params[:token])
      refresh_token.revoke_family
    elsif access_token = Oauth::AccessToken.find_by_raw_token(params[:token])
      access_token.revoke
    end

    head :ok
  end
end
