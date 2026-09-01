# Device-facing OAuth endpoints. These speak the OAuth protocol to programs,
# not browsers, so they sit outside ApplicationController: no cookie
# authentication, no CSRF (clients authenticate per request), no browser
# guard, and errors render as OAuth JSON error responses.
class Oauth::BaseController < ActionController::Base
  skip_forgery_protection

  rate_limit to: 30, within: 1.minute, with: -> { render_rate_limit_exceeded }

  before_action :prevent_response_caching

  rescue_from Oauth::Error, with: :render_oauth_error

  private
    def require_recognized_client
      unless params[:client_id] == Oauth::CLIENT_ID
        raise Oauth::Error.invalid_client
      end
    end

    def prevent_response_caching
      response.headers["Cache-Control"] = "no-store"
    end

    def render_oauth_error(error)
      render json: error, status: error.http_status
    end

    def render_rate_limit_exceeded
      response.headers["Retry-After"] = "60"
      render json: Oauth::Error.slow_down("Too many requests"), status: :too_many_requests
    end
end
