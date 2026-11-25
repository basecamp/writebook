module Authentication
  extend ActiveSupport::Concern
  include SessionLookup, TokenLookup

  included do
    before_action :refuse_read_only_token_access
    before_action :require_authentication
    helper_method :authenticated_by, :signed_in?

    protect_from_forgery with: :exception, unless: -> { authenticated_by.oauth_token? }
  end

  class_methods do
    def require_unauthenticated_access(**options)
      allow_unauthenticated_access **options
      before_action :redirect_signed_in_user_to_root, **options
    end

    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
      before_action :resume_authentication, **options
    end

    # Read-only tokens (API tokens and read-only OAuth access tokens) are
    # refused everywhere except the reading actions that opt in here. Opting in
    # is per action, never for a whole controller of writes, and the token
    # still only authenticates GET requests.
    def allow_read_only_token_access(**options)
      skip_before_action :refuse_read_only_token_access, **options
    end
  end

  private
    def signed_in?
      Current.user.present?
    end

    def require_authentication
      restore_authentication || request_authentication
    end

    # Pages anyone may read still answer 401 to a bearer token that doesn't
    # authenticate, so a revoked or mistyped token fails loudly instead of
    # quietly reading as an anonymous visitor.
    def resume_authentication
      restore_authentication || (request_token_authentication if bearer_token.present?)
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
      if read_request? || !find_read_only_token_by_header
        resume_token
      end
    end

    def resume_token
      if access_token = find_access_token_by_header
        access_token.record_use
        Current.user = access_token.user
        set_authenticated_by(:oauth_token)
      elsif api_token = find_api_token_by_header
        api_token.record_use
        Current.user = api_token.user
        set_authenticated_by(:api_token)
      end
    end

    # Pages a reader shouldn't reach with a read-only token (settings with
    # sign-in links, the OAuth approval page, and every write) answer 403, so
    # the token can never be turned into a session or a full-access token.
    def refuse_read_only_token_access
      if bearer_token.present? && find_read_only_token_by_header
        request_full_access
      end
    end

    def read_request?
      request.get? || request.head?
    end

    def request_token_authentication
      if read_request? || !find_read_only_token_by_header
        response.headers["WWW-Authenticate"] = 'Bearer error="invalid_token"'
        head :unauthorized
      else
        request_full_access
      end
    end

    def request_full_access
      response.headers["WWW-Authenticate"] = 'Bearer error="insufficient_scope"'
      head :forbidden
    end

    # A bearer token, even a full-access OAuth one, must not mint a token or a
    # sign-in that outlives it, so those are only done from a signed-in browser.
    def ensure_signed_in_with_a_session
      head :forbidden unless authenticated_by.session?
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
