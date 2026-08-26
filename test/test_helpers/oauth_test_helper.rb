module OauthTestHelper
  DAVIDS_ACCESS_TOKEN = "wb_at_#{"d" * 64}"
  DAVIDS_EXPIRED_ACCESS_TOKEN = "wb_at_#{"e" * 64}"
  DAVIDS_REFRESH_TOKEN = "wb_rt_#{"d" * 64}"
  JASONS_ACCESS_TOKEN = "wb_at_#{"j" * 64}"
  JASONS_REFRESH_TOKEN = "wb_rt_#{"j" * 64}"
  JZS_ACCESS_TOKEN = "wb_at_#{"z" * 64}"

  def bearer_headers(token = DAVIDS_ACCESS_TOKEN)
    { "Authorization" => "Bearer #{token}" }
  end
end
