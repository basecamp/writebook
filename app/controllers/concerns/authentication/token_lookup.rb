module Authentication::TokenLookup
  def find_access_token_by_header
    Oauth::AccessToken.find_active_by_raw_token bearer_token
  end

  def bearer_token
    request.authorization.to_s[/\ABearer (.+)\z/i, 1]
  end
end
