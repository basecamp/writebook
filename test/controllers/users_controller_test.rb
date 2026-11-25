require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @join_code = accounts(:signal).join_code
  end

  test "new" do
    get join_url(@join_code)
    assert_response :success
  end

  test "new does not allow a signed in user" do
    sign_in :david

    get join_url(@join_code)
    assert_redirected_to root_url
  end

  test "new requires a join code" do
    get join_url("not")
    assert_response :not_found
  end

  test "create" do
    assert_difference -> { User.count }, 1 do
      post join_url(@join_code), params: { user: { name: "New Person", email_address: "new@example.com", password: "secret123456" } }
    end

    assert_redirected_to root_url

    user = User.last
    assert_equal user.id, Session.find_by(token: parsed_cookies.signed[:session_token]).user.id
  end

  test "creating a new user with an existing email address redirects to login screen" do
    assert_no_difference -> { User.count } do
      post join_url(@join_code), params: { user: { name: "Another David", email_address: users(:david).email_address, password: "secret123456" } }
    end

    assert_redirected_to new_session_url(email_address: users(:david).email_address)
  end

  test "update" do
    sign_in :david
    assert users(:david).administrator?

    put user_url(users(:kevin)), params: { user: { role: "administrator" } }

    assert_redirected_to users_url
    assert users(:kevin).reload.administrator?
  end

  test "update does not allow non-admins to change roles" do
    sign_in :kevin
    assert_not users(:kevin).administrator?

    put user_url(users(:kevin)), params: { user: { role: "administrator" } }

    assert_response :forbidden
    assert_not users(:kevin).reload.administrator?
  end

  test "destroy" do
    sign_in :david

    assert_difference -> { User.active.count }, -1 do
      delete user_url(users(:kevin))
    end

    assert_redirected_to users_url
    assert_nil User.active.find_by(id: users(:kevin).id)
  end

  test "destroy is not allowed to non-admins" do
    sign_in :kevin

    delete user_url(users(:david))
    assert_response :forbidden
  end

  test "index as JSON for an administrator" do
    get users_url(format: :json), headers: bearer_headers

    assert_response :success
    assert_equal join_url(@join_code), response.parsed_body["join_url"]
    assert response.parsed_body["can_administer"]
    assert_equal User.active.ids, response.parsed_body["users"].map { it["id"] }
    assert_equal({ "id" => users(:david).id, "name" => "David", "role" => "administrator", "current" => true },
      response.parsed_body["users"].find { it["id"] == users(:david).id })
    assert_equal({ "id" => users(:kevin).id, "name" => "Kevin", "role" => "member", "current" => false },
      response.parsed_body["users"].find { it["id"] == users(:kevin).id })
  end

  test "index as JSON for a member shows the join link like the page does, but can't administer" do
    get users_url(format: :json), headers: bearer_headers(JZS_ACCESS_TOKEN)

    assert_response :success
    assert_equal join_url(@join_code), response.parsed_body["join_url"]
    assert_not response.parsed_body["can_administer"]
    assert_equal [ users(:jz).id ], response.parsed_body["users"].select { it["current"] }.map { it["id"] }
  end

  test "update as JSON" do
    patch user_url(users(:kevin), format: :json), headers: bearer_headers, params: { user: { role: "administrator" } }

    assert_response :success
    assert_equal({ "id" => users(:kevin).id, "name" => "Kevin", "role" => "administrator" }, response.parsed_body)
    assert users(:kevin).reload.administrator?
  end

  test "update as JSON is not allowed to non-admins" do
    patch user_url(users(:kevin), format: :json), headers: bearer_headers(JZS_ACCESS_TOKEN), params: { user: { role: "administrator" } }

    assert_response :forbidden
    assert_not users(:kevin).reload.administrator?
  end

  test "nobody can change their own role" do
    sign_in :david
    put user_url(users(:david)), params: { user: { role: "member" } }
    assert_response :forbidden

    patch user_url(users(:david), format: :json), headers: bearer_headers, params: { user: { role: "member" } }
    assert_response :forbidden

    assert users(:david).reload.administrator?
  end

  test "destroy as JSON" do
    assert_difference -> { User.active.count }, -1 do
      delete user_url(users(:kevin), format: :json), headers: bearer_headers
    end

    assert_response :no_content
    assert_not users(:kevin).reload.active?
  end

  test "destroy as JSON is not allowed to non-admins" do
    assert_no_difference -> { User.active.count } do
      delete user_url(users(:kevin), format: :json), headers: bearer_headers(JZS_ACCESS_TOKEN)
    end

    assert_response :forbidden
  end

  test "nobody can remove themselves" do
    sign_in :david

    assert_no_difference -> { User.active.count } do
      delete user_url(users(:david))
      assert_response :forbidden

      delete user_url(users(:david), format: :json), headers: bearer_headers
      assert_response :forbidden
    end
  end

  test "read-only tokens can't change roles or remove people" do
    [ KEVINS_API_TOKEN, KEVINS_READ_ONLY_ACCESS_TOKEN ].each do |token|
      patch user_url(users(:jz), format: :json), headers: bearer_headers(token), params: { user: { role: "administrator" } }
      assert_response :forbidden

      delete user_url(users(:jz), format: :json), headers: bearer_headers(token)
      assert_response :forbidden
    end

    assert users(:jz).reload.member?
    assert users(:jz).active?
  end
end
