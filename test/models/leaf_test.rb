require "test_helper"

class LeafTest < ActiveSupport::TestCase
  test "slug is generated from title" do
    leaf = Leaf.new(title: "Hello, World!")
    assert_equal "hello-world", leaf.slug
  end

  test "slug is never completely blank" do
    leaf = Leaf.new(title: "")
    assert_equal "-", leaf.slug
  end

  test "fingerprint changes with the title and the content, for every leafable type" do
    [ leaves(:welcome_page), leaves(:welcome_section), leaves(:reading_picture) ].each do |leaf|
      original = leaf.fingerprint
      assert_equal original, leaf.reload.fingerprint

      leaf.update! title: "#{leaf.title} again"
      assert_not_equal original, leaf.fingerprint
    end
  end

  test "fingerprint changes when a page body changes" do
    leaf = leaves(:welcome_page)
    original = leaf.fingerprint

    leaf.leafable.body.update! content: "Rewritten."
    assert_not_equal original, leaf.reload.fingerprint
  end
end
