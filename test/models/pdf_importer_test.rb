require "test_helper"

class PdfImporterTest < ActiveSupport::TestCase
  setup do
    @book     = books(:handbook)
    @pdf_path = file_fixture("sample.pdf")
  end

  test "imports one leaf per PDF page" do
    assert_difference -> { @book.leaves.active.count }, +2 do
      PdfImporter.new(@book, @pdf_path).import
    end
  end

  test "returns the imported leaves" do
    leaves = PdfImporter.new(@book, @pdf_path).import
    assert_equal 2, leaves.size
    assert leaves.all? { |l| l.is_a?(Leaf) }
  end

  test "uses the first line of each page as the leaf title" do
    leaves = PdfImporter.new(@book, @pdf_path).import
    assert_equal "Introduction", leaves.first.title
    assert_equal "Chapter Two", leaves.second.title
  end

  test "stores page body text as markdown content" do
    leaves = PdfImporter.new(@book, @pdf_path).import
    assert_includes leaves.first.page.body.content, "This is the first page"
    assert_includes leaves.second.page.body.content, "This is the second page"
  end

  test "skips PDF pages with no extractable content" do
    assert_no_difference -> { Page.count } do
      PdfImporter.new(@book, file_fixture("blank.pdf")).import
    end
  end

  test "raises InvalidPdfError for a malformed file" do
    assert_raises PdfImporter::InvalidPdfError do
      PdfImporter.new(@book, StringIO.new("this is not a pdf"))
    end
  end

  test "raises InvalidPdfError when pdf_io is nil" do
    assert_raises PdfImporter::InvalidPdfError do
      PdfImporter.new(@book, nil)
    end
  end

  test "raises InvalidPdfError when pdf_io is blank" do
    assert_raises PdfImporter::InvalidPdfError do
      PdfImporter.new(@book, "")
    end
  end

  test "imports embedded pictures as Picture leaves" do
    leaves = PdfImporter.new(@book, file_fixture("sample_with_image.pdf")).import
    picture_leaves = leaves.select(&:picture?)
    assert_equal 1, picture_leaves.size
    assert picture_leaves.first.leafable.image.attached?
  end

  test "creates a Page leaf and a Picture leaf for pages with both text and an image" do
    leaves = PdfImporter.new(@book, file_fixture("sample_with_image.pdf")).import
    assert_equal 3, leaves.size
    assert_equal 2, leaves.count(&:page?)
    assert_equal 1, leaves.count(&:picture?)
  end

  test "Picture leaf inherits the title of the page it came from" do
    leaves = PdfImporter.new(@book, file_fixture("sample_with_image.pdf")).import
    picture_leaf = leaves.find(&:picture?)
    assert_equal "Chapter One", picture_leaf.title
  end
end
