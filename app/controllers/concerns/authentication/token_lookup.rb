module Authentication::TokenLookup
  def find_access_token_by_header
    Oauth::AccessToken.find_active_by_raw_token bearer_token
  end

  def find_api_token_by_header
    unless defined?(@api_token_by_header)
      @api_token_by_header = ApiToken.find_by_raw_token(bearer_token)
    end

    @api_token_by_header
  end

  def bearer_token
    request.authorization.to_s[/\ABearer (.+)\z/i, 1]
  end
end
