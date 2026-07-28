require "test_helper"

class PictureTest < ActiveSupport::TestCase
  test "markable returns caption" do
    picture = Picture.new(caption: "A great picture")

    assert_equal "A great picture", picture.markable
  end

  test "markable returns nil when caption is nil" do
    picture = Picture.new(caption: nil)

    assert_nil picture.markable
  end

  test "large_image is the resized variant of a variable image" do
    assert_kind_of ActiveStorage::VariantWithRecord, pictures(:reading).large_image
  end

  test "large_image is the original image when the image cannot be resized" do
    picture = pictures(:reading)
    picture.image.attach io: file_fixture("pixel.bmp").open, filename: "pixel.bmp", content_type: "image/bmp"

    assert_equal picture.image, picture.large_image
  end
end
