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

  test "show includes link to markdown format" do
    get leafable_slug_path(leaves(:welcome_page))

    assert_response :success
    assert_select "link[rel=\"alternate\"][type=\"text/markdown\"][href=\"#{leafable_slug_path(leaves(:welcome_page), format: :md)}\"]"
  end

  test "show with markdown format returns raw markdown content" do
    leaves(:welcome_page).leafable.update!(body: "## Hello\n\nThis is **bold** text.")

    get leafable_slug_path(leaves(:welcome_page), format: :md)

    assert_response :success
    assert_in_body "## Hello"
    assert_in_body "This is **bold** text."
    assert_in_body "title: \"Welcome to The Handbook!\""
  end

  test "show with markdown format for section returns body" do
    leaves(:welcome_section).leafable.update!(body: "Section Body Content")

    get leafable_slug_path(leaves(:welcome_section), format: :md)

    assert_response :success
    assert_in_body "Section Body Content"
    assert_in_body "title: \"The Welcome Section\""
  end

  test "show with markdown format for picture returns caption" do
    leaves(:reading_picture).leafable.update!(caption: "A beautiful picture")

    get leafable_slug_path(leaves(:reading_picture), format: :md)

    assert_response :success
    assert_in_body "A beautiful picture"
    assert_in_body "title: \"Reading\""
  end

  test "show a picture whose image cannot be resized" do
    leaves(:reading_picture).leafable.image.attach io: file_fixture("pixel.bmp").open,
      filename: "pixel.bmp", content_type: "image/bmp"

    get leafable_slug_path(leaves(:reading_picture))

    assert_response :success
    assert_select "figure img[src*=\"pixel.bmp\"]"
  end

  test "show with markdown format does not escape HTML entities" do
    leaves(:welcome_page).leafable.update!(body: "This has <a href='http://example.com'>a link</a>")

    get leafable_slug_path(leaves(:welcome_page), format: :md)

    assert_response :success
    assert_in_body "<a href='http://example.com'>"
    assert_not_in_body "&lt;"
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
