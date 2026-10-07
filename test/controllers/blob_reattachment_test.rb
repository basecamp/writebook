require "test_helper"

# Anyone who has seen a file has its signed blob id: it's in the file's URL. Attaching
# a file by that id to a book of your own would make it readable through that book,
# whatever access you have to the book it came from.
class BlobReattachmentTest < ActionDispatch::IntegrationTest
  setup do
    ActiveStorage::Current.url_options = { host: "www.example.com", protocol: "http" }

    books(:manual).cover.attach \
      io: file_fixture("reading.webp").open, filename: "reading.webp", content_type: "image/webp"
    @cover = books(:manual).cover.blob
    @disk_path = URI.parse(@cover.url).request_uri
  end

  test "a reader whose access is revoked can't get a cover back by putting it on a new book" do
    sign_in :jz
    get @disk_path
    assert_response :success

    accesses(:jz_manual).destroy!

    assert_difference -> { Book.count }, +1 do
      post books_path, params: { book: { title: "Mine", cover: @cover.signed_id } }
    end

    assert_not Book.last.cover.attached?
    assert_not_reattached
  end

  test "a cover can't be replaced with another book's file" do
    attach_handbook_cover
    sign_in :kevin

    patch book_path(books(:handbook)), params: { book: { cover: @cover.signed_id } }

    assert_equal "white-rabbit.webp", books(:handbook).reload.cover.filename.to_s
    assert_not_reattached
  end

  test "a new picture can't use another book's file" do
    sign_in :kevin

    post book_pictures_path(books(:handbook), format: :turbo_stream), params: {
      leaf: { title: "Mine" }, picture: { image: @cover.signed_id } }

    assert_not_reattached
  end

  test "a picture can't be replaced with another book's file" do
    sign_in :kevin

    put leafable_path(leaves(:reading_picture)), params: { picture: { image: @cover.signed_id } }

    assert_equal "reading.webp", leaves(:reading_picture).reload.picture.image.filename.to_s
    assert_not_reattached
  end

  test "a cover uploaded with a new book is attached" do
    sign_in :kevin

    post books_path, params: { book: { title: "Mine", cover: fixture_file_upload("reading.webp", "image/webp") } }

    assert_equal "reading.webp", Book.last.cover.filename.to_s
  end

  test "a cover uploaded to an existing book replaces its cover" do
    attach_handbook_cover
    sign_in :kevin

    patch book_path(books(:handbook)), params: { book: { cover: fixture_file_upload("reading.webp", "image/webp") } }

    assert_equal "reading.webp", books(:handbook).reload.cover.filename.to_s
  end

  test "a picture uploaded with a new picture page is attached" do
    sign_in :kevin

    assert_difference -> { books(:handbook).leaves.count }, +1 do
      post book_pictures_path(books(:handbook), format: :turbo_stream), params: {
        leaf: { title: "Mine" }, picture: { image: fixture_file_upload("reading.webp", "image/webp") } }
    end

    assert_equal "reading.webp", books(:handbook).leaves.last.picture.image.filename.to_s
  end

  private
    def attach_handbook_cover
      books(:handbook).cover.attach \
        io: file_fixture("white-rabbit.webp").open, filename: "white-rabbit.webp", content_type: "image/webp"
    end

    def assert_not_reattached
      assert_equal [ books(:manual) ], ActiveStorage::Attachment.where(blob: @cover).map(&:record)

      sign_out if cookies[:session_token].present?
      get @disk_path
      assert_response :not_found
    end
end
