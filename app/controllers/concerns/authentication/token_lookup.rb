module Authentication::TokenLookup
  def find_access_token_by_header
    unless defined?(@access_token_by_header)
      @access_token_by_header = Oauth::AccessToken.find_active_by_raw_token(bearer_token)
    end

    @access_token_by_header
  end

  def find_read_only_token_by_header
    if access_token = find_access_token_by_header
      access_token if access_token.read_only?
    else
      find_api_token_by_header
    end
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
