module SessionTestHelper
  def parsed_cookies
    ActionDispatch::Cookies::CookieJar.build(request, cookies.to_hash)
  end

  def sign_in(user)
    user = users(user) unless user.is_a? User
    post session_url, params: { email_address: user.email_address, password: "secret123456" }
    assert cookies[:session_token].present?
  end

  def sign_out
    delete session_url
    assert_not cookies[:session_token].present?
  end

  def bearer_key_header(user)
    user = users(user) unless user.is_a? User
    { "Authorization" => "Bearer #{user.bearer_key}" }
  end
end
