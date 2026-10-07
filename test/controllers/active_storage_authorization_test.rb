require "test_helper"

class ActiveStorageAuthorizationTest < ActionDispatch::IntegrationTest
  setup do
    ActiveStorage::Current.url_options = { host: "www.example.com", protocol: "http" }
    books(:handbook).update! published: true
  end

  test "a published book's cover is served to anyone" do
    cover = attach_cover

    get rails_blob_path(cover)
    assert_response :redirect

    get disk_path_for(cover)
    assert_response :success
    assert_equal file_fixture("reading.webp").binread, response.body
  end

  test "unpublishing a book revokes its cover's URLs" do
    cover = attach_cover
    redirect_path, disk_path = rails_blob_path(cover), disk_path_for(cover)

    books(:handbook).update! published: false

    get redirect_path
    assert_response :not_found

    get disk_path
    assert_response :not_found
  end

  test "unpublishing a book revokes its picture variants' URLs" do
    variant = attach_picture.variant(:large).processed
    redirect_path, disk_path = rails_representation_path(variant), disk_path_for(variant)

    books(:handbook).update! published: false

    get redirect_path
    assert_response :not_found

    get disk_path
    assert_response :not_found
  end

  test "unpublishing a book revokes the disk URL behind a page upload" do
    upload = attach_upload_to_welcome_page
    get action_text_markdown_upload_path(slug: upload.slug)
    disk_path = URI.parse(response.location).request_uri

    books(:handbook).update! published: false

    get disk_path
    assert_response :not_found
  end

  test "an unpublished book's images are served to its readers, but not publicly cached" do
    books(:handbook).update! published: false
    cover = attach_cover

    sign_in :jz
    get disk_path_for(cover)

    assert_response :success
    assert_no_match "public", response.headers["Cache-Control"].to_s
  end

  test "a reader whose access is revoked can't load an unpublished book's images" do
    books(:handbook).update! published: false
    cover = attach_cover

    sign_in :jz
    accesses(:jz_handbook).destroy!
    get disk_path_for(cover)

    assert_response :not_found
  end

  test "a published book's images are not left in shared caches" do
    cover = attach_cover

    get disk_path_for(cover)

    assert_response :success
    assert_no_match "public", response.headers["Cache-Control"].to_s
  end

  test "a blob attached to nothing is not served" do
    blob = ActiveStorage::Blob.create_and_upload! \
      io: file_fixture("reading.webp").open, filename: "reading.webp", content_type: "image/webp"

    get rails_blob_path(blob)
    assert_response :not_found

    get disk_path_for(blob)
    assert_response :not_found
  ensure
    blob&.purge
  end

  test "proxy routes are not served" do
    cover = attach_cover
    variant = attach_picture.variant(:large).processed

    get rails_storage_proxy_path(cover)
    assert_response :not_found

    get rails_storage_proxy_path(variant)
    assert_response :not_found
  end

  private
    def attach_cover
      books(:handbook).cover.attach \
        io: file_fixture("reading.webp").open, filename: "reading.webp", content_type: "image/webp"
      books(:handbook).cover
    end

    def attach_picture
      pictures(:reading).image.attach \
        io: file_fixture("reading.webp").open, filename: "reading.webp", content_type: "image/webp"
      pictures(:reading).image
    end

    def attach_upload_to_welcome_page
      markdown = pages(:welcome).body.tap(&:save!)
      markdown.uploads.attach io: file_fixture("reading.webp").open, filename: "reading.webp", content_type: "image/webp"
      markdown.uploads.last
    end

    def disk_path_for(attachable)
      URI.parse(attachable.url).request_uri
    end
end
