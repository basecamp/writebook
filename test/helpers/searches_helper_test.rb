require "test_helper"

class SearchesHelperTest < ActionView::TestCase
  test "sanitize_search_result preserves mark tags" do
    assert_equal "<mark>findme</mark> text", sanitize_search_result("<mark>findme</mark> text")
  end

  test "sanitize_search_result strips non-mark tags" do
    assert_equal "findme bold", sanitize_search_result("<b>findme</b> <b>bold</b>")
  end

  test "sanitize_search_result encodes entities" do
    assert_equal "Tom &amp; Jerry", sanitize_search_result("Tom & Jerry")
  end

  test "sanitize_search_result strips attributes from mark tags" do
    assert_equal "<mark>findme</mark> text", sanitize_search_result('<mark class="hidden">findme</mark> text')
  end
end
