require "test_helper"

class PageTest < ActiveSupport::TestCase
  test "html preview" do
    page = Page.new(body: "# Hello\n\nWorld!")

    assert_match /<h1>Hello<\/h1>/, page.html_preview
    assert_match /<p>World!<\/p>/, page.html_preview
  end

  test "markable returns raw markdown content" do
    page = Page.new(body: "## Markdown Content\n\nWith **bold** text.")

    assert_equal "## Markdown Content\n\nWith **bold** text.", page.markable
  end

  test "markable returns empty string when body is empty" do
    page = Page.new(body: "")

    assert_equal "", page.markable
  end

  test "searchable_content re-encodes HTML entities decoded by to_plain_text" do
    page = Page.new(body: "5 < 10 & 10 > 5")

    assert_includes page.searchable_content, "5 &lt; 10 &amp; 10 &gt; 5"
    assert page.searchable_content.html_safe?
  end
end
