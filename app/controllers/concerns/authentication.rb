module Authentication
  extend ActiveSupport::Concern
  include SessionLookup, TokenLookup

  included do
    before_action :require_authentication
    helper_method :signed_in?

    protect_from_forgery with: :exception, unless: -> { authenticated_by.oauth_token? }
  end

  class_methods do
    def require_unauthenticated_access(**options)
      allow_unauthenticated_access **options
      before_action :redirect_signed_in_user_to_root, **options
    end

    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
      before_action :restore_authentication, **options
    end
  end

  private
    def signed_in?
      Current.user.present?
    end

    def require_authentication
      restore_authentication || request_authentication
    end

    def restore_authentication
      if bearer_token.present?
        resume_token_access
      elsif session = find_session_by_cookie
        resume_session session
      end
    end

    # A presented-but-invalid bearer token must answer 401 rather than fall
    # through to cookie authentication or the sign-in page.
    def request_authentication
      if bearer_token.present?
        request_token_authentication
      else
        session[:return_to_after_authenticating] = request.url
        redirect_to new_session_url
      end
    end

    def resume_token_access
      if access_token = find_access_token_by_header
        access_token.record_use
        Current.user = access_token.user
        set_authenticated_by(:oauth_token)
      end
    end

    def request_token_authentication
      response.headers["WWW-Authenticate"] = 'Bearer error="invalid_token"'
      head :unauthorized
    end

    def redirect_signed_in_user_to_root
      redirect_to root_url if signed_in?
    end

    def start_new_session_for(user)
      user.sessions.start!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        authenticated_as session
      end
    end

    def resume_session(session)
      session.resume user_agent: request.user_agent, ip_address: request.remote_ip
      authenticated_as session
    end

    def terminate_current_session
      Current.session&.destroy!
      reset_session
      remove_authentication_cookie
    end

    def authenticated_as(session)
      Current.session = session
      set_authenticated_by(:session)
      set_authentication_cookie(session)
    end

    def post_authenticating_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    def set_authentication_cookie(session)
      cookies.signed.permanent[:session_token] = { value: session.token, httponly: true, same_site: :lax }
    end

    def remove_authentication_cookie
      cookies.delete(:session_token)
    end

    def set_authenticated_by(method)
      @authenticated_by = method.to_s.inquiry
    end

    def authenticated_by
      @authenticated_by ||= "".inquiry
    end
end
