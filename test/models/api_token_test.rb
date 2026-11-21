require "test_helper"

class ApiTokenTest < ActiveSupport::TestCase
  test "generate keeps the raw token in memory and stores its digest" do
    token = users(:kevin).api_tokens.generate!(name: "Script")

    assert_match(/\Awb_api_\h{64}\z/, token.raw_token)
    assert_equal token, ApiToken.find_by_raw_token(token.raw_token)
    assert_not_equal token.raw_token, token.reload.token_digest
  end

  test "find_by_raw_token ignores blank, unknown and deactivated users' tokens" do
    assert_nil ApiToken.find_by_raw_token(nil)
    assert_nil ApiToken.find_by_raw_token("")
    assert_nil ApiToken.find_by_raw_token("wb_api_unknown")

    assert_equal api_tokens(:kevins), ApiToken.find_by_raw_token(KEVINS_API_TOKEN)
    users(:kevin).update!(active: false)
    assert_nil ApiToken.find_by_raw_token(KEVINS_API_TOKEN)
  end

  test "deactivating a user deletes their tokens" do
    assert_difference -> { ApiToken.count }, -1 do
      users(:kevin).deactivate
    end
  end

  test "record_use updates last_used_at at most once an hour" do
    token = api_tokens(:kevins)

    freeze_time do
      token.record_use
      assert_equal Time.current, token.last_used_at

      travel 30.minutes
      token.record_use
      assert_equal 30.minutes.ago, token.last_used_at
    end
  end
end
