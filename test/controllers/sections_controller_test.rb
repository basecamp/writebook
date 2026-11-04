require "test_helper"

class SectionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :kevin
  end

  test "new is not available" do
    get "#{book_sections_path(books(:handbook))}/new"

    assert_response :not_found
  end

  test "create" do
    post book_sections_path(books(:handbook), format: :turbo_stream)
    assert_response :success

    new_section = Section.last
    assert_equal "Section", new_section.title
    assert_equal books(:handbook), new_section.leaf.book
  end

  test "update" do
    put leafable_path(leaves(:welcome_section)), params: {
      leaf: { title: "Title" },
      section: { body: "Section body" }
    }
    assert_response :success

    section = leaves(:welcome_section).reload.leafable
    assert_equal "Title", section.title
    assert_equal "Section body", section.body
  end

  test "update with no body supplied" do
    put leafable_path(leaves(:welcome_section)), params: { leaf: { title: "New title" } }
    assert_response :success

    section = leaves(:welcome_section).reload.leafable
    assert_equal "New title", section.title
    assert_equal "New title", section.body
  end
end
