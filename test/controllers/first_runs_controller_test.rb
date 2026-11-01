require "test_helper"

class FirstRunsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Book.destroy_all
    User.destroy_all
    Account.destroy_all
  end

  test "new" do
    get first_run_url
    assert_response :success
  end

  test "new is not permitted when users exist" do
    create_user

    get first_run_url
    assert_redirected_to root_url
  end

  test "create" do
    assert_difference -> { User.count }, 1 do
      post first_run_url, params: { user: { name: "New Person", email_address: "new@example.com", password: "secret123456" } }
    end

    assert_redirected_to root_url

    assert parsed_cookies.signed[:session_token]
  end

  test "create is not permitted when users exist" do
    create_user

    assert_no_difference -> { User.count } do
      post first_run_url, params: { user: { name: "New Person", email_address: "new@example.com", password: "secret123456" } }
    end

    assert_redirected_to root_url
  end

  test "create redirects without a new administrator when another first run has already created the account" do
    Account.create!(name: "Writebook")

    assert_no_difference -> { User.count } do
      post first_run_path, params: { user: { name: "New Person", email_address: "new@example.com", password: "secret123456" } }
    end

    assert_redirected_to root_path
    assert_nil parsed_cookies.signed[:session_token]
  end

  private
    def create_user
      User.create! \
        name: "Existing Person",
        email_address: "user@example.com",
        password: "secret123456"
    end
end
