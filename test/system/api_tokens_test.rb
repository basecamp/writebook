require "application_system_test_case"

class ApiTokensTest < ApplicationSystemTestCase
  test "create a read-only token and see it once" do
    sign_in "kevin@example.com"
    visit edit_user_profile_url(users(:kevin))

    fill_in "api_token[name]", with: "Runbook reader"
    click_on "Create a read-only API token"

    assert_text "Runbook reader: copy this token now"
    assert_match(/\Awb_api_\h{64}\z/, find_field("api_token").value)
  end
end
