require "test_helper"

class PdfPictureTest < ActiveSupport::TestCase
  test "returns empty array for pages with no pictures" do
    reader = PDF::Reader.new(file_fixture("sample.pdf"))
    assert_empty PdfPicture.extract_from(reader.pages[0])
  end

  test "extracts pictures from pages with embedded images" do
    reader   = PDF::Reader.new(file_fixture("sample_with_image.pdf"))
    pictures = PdfPicture.extract_from(reader.pages[1])
    assert_not_empty pictures
    assert_includes [ "image/jpeg", "image/png" ], pictures.first[:content_type]
  end

  test "each extracted picture has an io, filename, and content_type" do
    reader  = PDF::Reader.new(file_fixture("sample_with_image.pdf"))
    picture = PdfPicture.extract_from(reader.pages[1]).first

    assert picture[:io].respond_to?(:read)
    assert_not_nil picture[:filename]
    assert_not_nil picture[:content_type]
  end

  test "returns empty array when extraction raises" do
    broken = Object.new.tap { |s| s.define_singleton_method(:xobjects) { raise "boom" } }
    assert_empty PdfPicture.extract_from(broken)
  end
end
