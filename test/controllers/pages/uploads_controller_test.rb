require "test_helper"

class Pages::UploadsControllerTest < ActionDispatch::IntegrationTest
  test "a bearer key can upload to a page it can edit" do
    assert_changes -> { ActiveStorage::Attachment.count }, +1 do
      post book_page_uploads_path(books(:handbook), leaves(:welcome_page), format: :json),
        params: { file: fixture_file_upload("reading.webp", "image/webp") },
        headers: bearer_key_header(:david)
    end

    assert_response :created
    assert response.parsed_body["fileUrl"].start_with?("http://www.example.com/u/")
  end

  test "the returned URL serves publicly once the book is published" do
    post book_page_uploads_path(books(:handbook), leaves(:welcome_page), format: :json),
      params: { file: fixture_file_upload("reading.webp", "image/webp") },
      headers: bearer_key_header(:david)

    books(:handbook).update! published: true

    get response.parsed_body["fileUrl"]

    assert_response :redirect
    assert_equal "max-age=31556952, public", response.headers["Cache-Control"]
  end

  test "a reader's key cannot upload" do
    post book_page_uploads_path(books(:handbook), leaves(:welcome_page), format: :json),
      params: { file: fixture_file_upload("reading.webp", "image/webp") },
      headers: bearer_key_header(:jz)

    assert_response :forbidden
  end

  test "uploads only attach to pages" do
    post book_page_uploads_path(books(:handbook), leaves(:welcome_section), format: :json),
      params: { file: fixture_file_upload("reading.webp", "image/webp") },
      headers: bearer_key_header(:david)

    assert_response :unprocessable_entity
  end
end
