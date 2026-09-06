require "test_helper"

class BookTest < ActiveSupport::TestCase
  test "slug is generated from title" do
    book = Book.create!(title: "Hello, World!")
    assert_equal "hello-world", book.slug
  end

  test "press a leafable" do
    leaf = books(:manual).press Page.new(body: "Important words"), title: "Introduction"

    assert leaf.page?
    assert_equal "Important words", leaf.page.body.content.to_s
    assert_equal "Introduction", leaf.title
  end

  test "markable combines all leafables" do
    leaves(:welcome_page).leafable.update!(body: "Welcome page content")
    leaves(:summary_page).leafable.update!(body: "Summary page content")

    assert_includes books(:handbook).markable, "Welcome page content"
    assert_includes books(:handbook).markable, "Summary page content"
  end

  test "markable joins leafables with double newlines" do
    leaves(:welcome_page).leafable.update!(body: "Welcome content")
    leaves(:summary_page).leafable.update!(body: "Summary content")

    assert_includes books(:handbook).markable, "Welcome content\n\nSummary content"
  end

  test "markable only includes active leaves" do
    leaves(:welcome_page).leafable.update!(body: "Active content")
    leaves(:summary_page).trashed!

    assert_includes books(:handbook).markable, "Active content"
    assert_not_includes books(:handbook).markable, leaves(:summary_page).title
  end

  test "markable returns empty string for book with no leaves" do
    assert_equal "", books(:manual).markable
  end

  test "default_view defaults to grid" do
    book = Book.create!(title: "Test Book")
    assert_equal "grid", book.default_view
    assert book.grid_default_view?
  end

  test "allow_view_selector defaults to true" do
    book = Book.create!(title: "Test Book")
    assert book.allow_view_selector?
  end
end
