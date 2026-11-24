# OAuth error responses per RFC 6749 §5.2 and RFC 8628 §3.5, rendered as
# {"error": "invalid_grant", "error_description": "..."}. Token endpoint
# errors answer 400 except invalid_client, which answers 401.
class Oauth::Error < StandardError
  attr_reader :code, :description

  HTTP_STATUS_MAP = {
    invalid_request: :bad_request,
    invalid_client: :unauthorized,
    invalid_grant: :bad_request,
    unsupported_grant_type: :bad_request,
    access_denied: :bad_request,
    authorization_pending: :bad_request,
    slow_down: :bad_request,
    expired_token: :bad_request
  }.freeze

  class << self
    def invalid_request(description = nil)
      new :invalid_request, description || "The request is missing a required parameter or is otherwise malformed"
    end

    def invalid_client(description = nil)
      new :invalid_client, description || "Client authentication failed"
    end

    def invalid_grant(description = nil)
      new :invalid_grant, description || "The provided authorization grant is invalid, expired, or revoked"
    end

    def unsupported_grant_type(description = nil)
      new :unsupported_grant_type, description || "The grant type is not supported"
    end

    def access_denied(description = nil)
      new :access_denied, description || "The resource owner denied the request"
    end

    def authorization_pending(description = nil)
      new :authorization_pending, description || "The authorization request is still pending"
    end

    def slow_down(description = nil)
      new :slow_down, description || "Polling too frequently, please slow down"
    end

    def expired_token(description = nil)
      new :expired_token, description || "The device code has expired"
    end
  end

  def initialize(code, description = nil)
    @code = code.to_sym
    @description = description
    super(description || code.to_s)
  end

  def http_status
    HTTP_STATUS_MAP.fetch(@code, :bad_request)
  end

  def as_json(*)
    { error: @code.to_s, error_description: @description }.compact
  end
end
