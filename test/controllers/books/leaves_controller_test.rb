require "test_helper"

class Books::LeavesControllerTest < ActionDispatch::IntegrationTest
  test "index returns the ordered manifest" do
    get book_leaves_path(books(:handbook), format: :json), headers: bearer_key_header(:david)

    assert_response :success

    manifest = response.parsed_body
    assert_equal books(:handbook).leaves.active.count, manifest.size
    assert_equal (0...manifest.size).to_a, manifest.map { it["position"] }

    welcome = manifest.find { it["id"] == leaves(:welcome_page).id }
    assert_equal "Page", welcome["leafable_type"]
    assert_equal "Welcome to The Handbook!", welcome["title"]
    assert_equal "welcome-to-the-handbook", welcome["slug"]
    assert_equal leafable_slug_url(leaves(:welcome_page)), welcome["url"]
  end

  test "index excludes trashed leaves" do
    leaves(:welcome_page).trashed!

    get book_leaves_path(books(:handbook), format: :json), headers: bearer_key_header(:david)

    assert_not_includes response.parsed_body.map { it["id"] }, leaves(:welcome_page).id
  end

  test "index requires authentication" do
    get book_leaves_path(books(:handbook), format: :json)

    assert_response :unauthorized
  end

  test "index also works with a signed-in session" do
    sign_in :david

    get book_leaves_path(books(:handbook), format: :json)

    assert_response :success
  end
end
