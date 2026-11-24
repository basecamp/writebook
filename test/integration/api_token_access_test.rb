require "test_helper"

class ApiTokenAccessTest < ActionDispatch::IntegrationTest
  setup do
    Leaf.reindex_all
  end

  test "reads the books, pages, manifests and search its user can read" do
    get books_path(format: :json), headers: api_headers
    assert_response :success
    assert_equal [ "Handbook" ], response.parsed_body.map { it["title"] }

    get book_slug_path(books(:handbook), format: :md), headers: api_headers
    assert_response :success
    assert_in_body "Thanks for reading!"

    get leafable_slug_path(leaves(:welcome_page), format: :md), headers: api_headers
    assert_response :success
    assert_in_body "This is _such_ a great handbook."

    get book_page_path(books(:handbook), leaves(:welcome_page), format: :json), headers: api_headers
    assert_response :success
    assert_equal "This is _such_ a great handbook.", response.parsed_body["body"]

    get book_manifest_path(books(:handbook), format: :json), headers: api_headers
    assert_response :success

    get search_path(format: :json, q: "Thanks"), headers: api_headers
    assert_response :success
    assert_equal [ leaves(:summary_page).id ], response.parsed_body["results"].map { it["id"] }

    get book_search_path(books(:handbook), format: :json, q: "Thanks"), headers: api_headers
    assert_response :success
    assert_equal [ leaves(:summary_page).id ], response.parsed_body["results"].map { it["id"] }
  end

  test "answers HEAD requests like GETs" do
    head book_manifest_path(books(:handbook), format: :json), headers: api_headers

    assert_response :success
  end

  test "does not read books its user has no access to" do
    get book_manifest_path(books(:manual), format: :json), headers: api_headers
    assert_response :not_found

    get book_slug_path(books(:manual), format: :md), headers: api_headers
    assert_response :not_found
  end

  test "authenticates without a session cookie and records when it was used" do
    freeze_time do
      get books_path(format: :json), headers: api_headers

      assert_not cookies[:session_token].present?
      assert_equal Time.current, api_tokens(:kevins).reload.last_used_at
    end
  end

  test "is refused on every write endpoint, even on books its user can edit" do
    assert books(:handbook).editable?(user: users(:kevin))

    write_routes.each do |verb, path|
      assert_no_changes -> { database_snapshot } do
        process verb, path, headers: api_headers, params: { book: { title: "Changed" }, leaf: { title: "Changed" }, page: { body: "Changed" } }
      end
      assert_response :forbidden, "expected #{verb.upcase} #{path} to be refused"
      assert_equal 'Bearer error="insufficient_scope"', response.headers["WWW-Authenticate"]
    end
  end

  test "can't open pages that would turn it into a session or a full-access token" do
    [
      edit_user_profile_path(users(:kevin)),
      user_profile_path(users(:kevin)),
      users_path,
      session_transfer_path(users(:kevin).transfer_id),
      oauth_device_verification_path,
      new_session_path,
      first_run_path,
      book_bookmark_path(books(:handbook)),
      edit_book_page_path(books(:handbook), leaves(:welcome_page)),
      new_book_path,
      edit_book_path(books(:handbook))
    ].each do |path|
      get path, headers: api_headers
      assert_response :forbidden, "expected GET #{path} to be refused"
    end
  end

  test "reads text only: uploads are refused" do
    get action_text_markdown_upload_path(slug: "anything.png"), headers: api_headers

    assert_response :forbidden
  end

  test "can't approve an OAuth device grant" do
    grant = Oauth::DeviceGrant.generate!

    patch oauth_device_verification_path, params: { user_code: grant.user_code, initiation_confirmed: "1" }, headers: api_headers

    assert_response :forbidden
    assert grant.reload.pending?
  end

  test "an unknown, revoked or deactivated user's token answers 401" do
    get books_path(format: :json), headers: api_headers("wb_api_nonsense")
    assert_response :unauthorized

    api_tokens(:kevins).destroy
    get books_path(format: :json), headers: api_headers
    assert_response :unauthorized

    token = users(:jz).api_tokens.generate!(name: "Script")
    users(:jz).deactivate
    get books_path(format: :json), headers: api_headers(token.raw_token)
    assert_response :unauthorized
  end

  private
    def api_headers(token = KEVINS_API_TOKEN)
      bearer_headers(token)
    end

    def write_routes
      Rails.application.routes.routes.filter_map do |route|
        controller = route.defaults[:controller]
        verbs = route.verb.split("|") - %w[ GET HEAD ]

        if verbs.any? && routed_to_application_action?(controller, route.defaults[:action])
          [ verbs.first.downcase.to_sym, route_path(route) ]
        end
      end.tap { assert it.size > 20, "expected to find the app's write routes" }
    end

    def routed_to_application_action?(controller, action)
      klass = "#{controller.to_s.camelize}Controller".safe_constantize
      klass && klass < ApplicationController && klass.action_methods.include?(action.to_s)
    end

    def route_path(route)
      route.path.spec.to_s
        .sub("(.:format)", "")
        .gsub("*slug", "file.txt")
        .gsub(/:\w+/) { |segment| segment == ":book_id" ? books(:handbook).id.to_s : leaves(:welcome_page).id.to_s }
    end

    def database_snapshot
      [ Book, Leaf, Page, Section, Picture, User, Access, Session, Account, Oauth::DeviceGrant, Oauth::AccessToken, ApiToken ]
        .map { |model| model.maximum(:updated_at) || model.count }
    end
end
