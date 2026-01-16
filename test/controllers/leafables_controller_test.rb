require "test_helper"

class LeafablesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :kevin
  end

  test "show" do
    get leafable_slug_path(leaves(:welcome_page))

    assert_response :success
    assert_select "p", "This is such a great handbook."
  end

  test "show markdown export" do
    get leafable_slug_path(leaves(:welcome_page), format: :md)

    assert_response :success
    assert_includes response.body, "### Welcome to The Handbook!"
    assert_includes response.body, "This is _such_ a great handbook."
  end

  test "show with public access to a published book" do
    sign_out
    books(:handbook).update!(published: true)

    get leafable_slug_path(leaves(:welcome_page))

    assert_response :success
    assert_select "p", "This is such a great handbook."
  end

  test "show highlights search terms" do
    Leaf.reindex_all
    get leafable_slug_path(leaves(:welcome_page)), params: { search: "great" }

    assert_response :success
    assert_select "mark", "great"
  end

  test "show does not allow public access to an unpublished book" do
    sign_out

    get leafable_slug_path(leaves(:welcome_page))

    assert_response :not_found
  end

  test "create" do
    assert_changes -> { books(:handbook).leaves.count }, +1 do
      post book_pages_path(books(:handbook), format: :turbo_stream), params: {
        leaf: { title: "Another page" }, page: { body: "With interesting words." }
      }
    end

    assert_response :success
  end

  test "create requires editor access" do
    books(:handbook).access_for(user: users(:kevin)).update! level: :reader

    assert_no_changes -> { books(:handbook).leaves.count } do
      post book_pages_path(books(:handbook), format: :turbo_stream), params: {
        leaf: { title: "Another page" }, page: { body: "With interesting words." }
      }
    end

    assert_response :forbidden
  end
end
