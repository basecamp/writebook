require "test_helper"

class PdfPageTest < ActiveSupport::TestCase
  setup do
    @reader = PDF::Reader.new(file_fixture("sample.pdf"))
  end

  test "uses the first line as title when it is a valid length" do
    assert_equal "Introduction", PdfPage.new(@reader.pages[0], 1).title
  end

  test "falls back to 'Page #' when first line is too short" do
    assert_equal "Page 3", PdfPage.new(stub_page("Hi\nsome body content"), 3).title
  end

  test "falls back to 'Page #' when first line is too long" do
    assert_equal "Page 2", PdfPage.new(stub_page("#{"A" * 101}\nsome body content"), 2).title
  end

  test "falls back to 'Page #' when text is blank" do
    assert_equal "Page 1", PdfPage.new(stub_page(""), 1).title
  end

  test "normalizes body by collapsing runs of blank lines into one" do
    assert_equal "Title\n\nsome content", PdfPage.new(stub_page("Title\n\n\n\nsome content"), 1).body
  end

  test "blank? is true when text and pictures are both empty" do
    assert PdfPage.new(stub_page(""), 1).blank?
  end

  test "blank? is false when text is present" do
    assert_not PdfPage.new(stub_page("Some text here on the page"), 1).blank?
  end

  private
    def stub_page(text)
      Object.new.tap do |p|
        p.define_singleton_method(:text) { text }
        p.define_singleton_method(:xobjects) { {} }
      end
    end
end
