require "test_helper"

class Accounts::JoinCodesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
  end

  test "create new join code" do
    assert_changes -> { accounts(:signal).reload.join_code } do
      post account_join_code_url
      assert_redirected_to users_url
    end
  end

  test "only administrators can create new join codes" do
    sign_in :jz
    post account_join_code_url
    assert_response :forbidden
  end

  test "create new join code as JSON" do
    assert_changes -> { accounts(:signal).reload.join_code } do
      post account_join_code_url(format: :json), headers: bearer_headers
    end

    assert_response :success
    assert_equal({ "join_url" => join_url(accounts(:signal).reload.join_code) }, response.parsed_body)
  end

  test "only administrators can create new join codes as JSON" do
    assert_no_changes -> { accounts(:signal).reload.join_code } do
      post account_join_code_url(format: :json), headers: bearer_headers(JZS_ACCESS_TOKEN)
    end

    assert_response :forbidden
  end
end
