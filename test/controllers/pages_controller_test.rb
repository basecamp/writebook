require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :kevin
  end

  test "show" do
    get leafable_path(sample_page_leaf("## Hello"))

    assert_response :ok
    assert_select "h2", text: /Hello/
  end

  test "show as markdown" do
    get leafable_path(leaves(:welcome_page), format: :md)

    assert_response :ok
    assert_includes response.body, "### Welcome to The Handbook!"
    assert_includes response.body, "This is _such_ a great handbook."
  end

  test "show sanitizes dangerous content" do
    get leafable_path(sample_page_leaf(%(<div id="test"><script>alert("ouch")</script></div>)))

    assert_select "#test", html: %(alert("ouch"))
  end

  test "show with HTML content in the markdown" do
    get leafable_path(sample_page_leaf(%(<div id="test"><div style="text-align:center;">Hello</div></div>)))

    assert_select "#test", html: %(<div style="text-align:center;">Hello</div>)
  end

  test "show with iframes" do
    get leafable_path(sample_page_leaf(%(<div id="test"><iframe src="http://example.com"></iframe></div>)))

    assert_select "#test", html: %(<iframe src="http://example.com"></iframe>)
  end

  test "show with tables in the markdown" do
    get leafable_path(sample_page_leaf(%(| name | food |\n| ---- | ---- |\n| Kevin | Pizza |)))

    assert_select "table th", text: "name"
    assert_select "table th", text: "food"
    assert_select "table td", text: "Kevin"
    assert_select "table td", text: "Pizza"
  end

  test "create" do
    post book_pages_path(books(:handbook), format: :turbo_stream), params: { leaf: { title: "Another page" }, page: { body: "With interesting words." } }
    assert_response :success

    new_page = Page.last
    assert_equal "Another page", new_page.title
    assert_equal "With interesting words.", new_page.body.content
    assert_equal books(:handbook), new_page.leaf.book
  end

  test "create with default params" do
    assert_changes -> { Page.count }, +1 do
      post book_pages_path(books(:handbook), format: :turbo_stream)
    end
    assert_response :success

    assert_equal "Untitled", Page.last.title
  end

  test "create at a specific position" do
    assert_changes -> { Page.count }, +1 do
      post book_pages_path(books(:handbook), format: :turbo_stream), params: { position: 2 }
    end
    assert_response :success

    assert_equal 2, books(:handbook).leaves.before(Page.last.leaf).count
  end

  test "update" do
    get edit_leafable_path(leaves(:welcome_page))
    assert_response :ok

    put leafable_path(leaves(:welcome_page)), params: { leaf: { title: "Better welcome" }, page: { body: "With even more interesting words." } }
    assert_response :no_content

    updated_page = Page.last
    assert_equal "Better welcome", updated_page.title
    assert_equal "With even more interesting words.", updated_page.body.content
  end

  private
    def sample_page_leaf(markdown)
      books(:handbook).press Page.new(body: markdown), title: "Sample"
    end
end
