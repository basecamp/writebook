require "test_helper"

class ActionText::Markdown::UploadsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :kevin
  end

  test "attach a file" do
    assert_changes -> { ActiveStorage::Attachment.count }, 1 do
      post action_text_markdown_uploads_url, params: {
        record_gid: uploads_signed_id_for(pages(:welcome)),
        attribute_name: "body",
        file: fixture_file_upload("reading.webp", "image/webp")
      }, as: :xhr
    end

    assert_response :success

    # Absolute URLs, so bodies mirrored into git render everywhere. A hostname
    # change means a one-time rewrite of stored bodies.
    assert JSON.parse(response.body)["fileUrl"].start_with?("http://www.example.com/u/")
  end

  test "a signed id minted for some other purpose can't be used to upload" do
    assert_no_changes -> { ActiveStorage::Attachment.count } do
      post action_text_markdown_uploads_url, params: {
        record_gid: pages(:welcome).to_signed_global_id.to_s,
        attribute_name: "body",
        file: fixture_file_upload("reading.webp", "image/webp")
      }, as: :xhr
    end

    assert_response :not_found
  end

  test "an expired signed id can't be used to upload" do
    record_gid = uploads_signed_id_for(pages(:welcome))

    travel ActionText::Markdown::UPLOADS_SIGNED_ID_EXPIRY + 1.hour do
      assert_no_changes -> { ActiveStorage::Attachment.count } do
        post action_text_markdown_uploads_url, params: {
          record_gid: record_gid,
          attribute_name: "body",
          file: fixture_file_upload("reading.webp", "image/webp")
        }, as: :xhr
      end
    end

    assert_response :not_found
  end

  test "a revoked collaborator can't upload with a signed id minted while an editor" do
    record_gid = uploads_signed_id_for(pages(:welcome))
    accesses(:kevin_handbook).destroy!

    assert_no_changes -> { ActiveStorage::Attachment.count } do
      post action_text_markdown_uploads_url, params: {
        record_gid: record_gid,
        attribute_name: "body",
        file: fixture_file_upload("reading.webp", "image/webp")
      }, as: :xhr
    end

    assert_response :not_found
  end

  test "a downgraded editor can't upload" do
    record_gid = uploads_signed_id_for(pages(:welcome))
    accesses(:kevin_handbook).update! level: :reader

    assert_no_changes -> { ActiveStorage::Attachment.count } do
      post action_text_markdown_uploads_url, params: {
        record_gid: record_gid,
        attribute_name: "body",
        file: fixture_file_upload("reading.webp", "image/webp")
      }, as: :xhr
    end

    assert_response :forbidden
  end

  test "a reader can't upload" do
    sign_in :jz

    assert_no_changes -> { ActiveStorage::Attachment.count } do
      post action_text_markdown_uploads_url, params: {
        record_gid: uploads_signed_id_for(pages(:welcome)),
        attribute_name: "body",
        file: fixture_file_upload("reading.webp", "image/webp")
      }, as: :xhr
    end

    assert_response :forbidden
  end

  test "view attached file" do
    books(:handbook).update! published: true
    attachment = attach_upload_to_welcome_page

    get action_text_markdown_upload_url(slug: attachment.slug)

    assert_response :redirect
    assert_match /\/rails\/active_storage\/.*\/reading\.webp/, @response.redirect_url
  end

  test "an attachment of a published book is publicly cacheable" do
    books(:handbook).update! published: true
    attachment = attach_upload_to_welcome_page

    get action_text_markdown_upload_url(slug: attachment.slug)

    assert_match "public", @response.headers["Cache-Control"]
  end

  test "an attachment of an unpublished book is not served to anonymous clients" do
    books(:handbook).update! published: false
    attachment = attach_upload_to_welcome_page

    reset!
    get action_text_markdown_upload_url(slug: attachment.slug)

    assert_response :not_found
  end

  test "an attachment of an unpublished book is not served to a user without access" do
    books(:handbook).update! published: false
    attachment = attach_upload_to_welcome_page

    accesses(:kevin_handbook).destroy!
    get action_text_markdown_upload_url(slug: attachment.slug)

    assert_response :not_found
  end

  test "an attachment of an unpublished book is served to a reader, but not publicly cached" do
    books(:handbook).update! published: false
    attachment = attach_upload_to_welcome_page

    sign_in :jz
    get action_text_markdown_upload_url(slug: attachment.slug)

    assert_response :redirect
    assert_no_match "public", @response.headers["Cache-Control"].to_s
  end

  private
    def uploads_signed_id_for(record)
      record.to_signed_global_id(
        expires_in: ActionText::Markdown::UPLOADS_SIGNED_ID_EXPIRY,
        for: ActionText::Markdown::UPLOADS_SIGNED_ID_PURPOSE
      ).to_s
    end

    def attach_upload_to_welcome_page
      markdown = pages(:welcome).body.tap(&:save!)
      markdown.uploads.attach fixture_file_upload("reading.webp", "image/webp")
      pages(:welcome).body.uploads.last
    end
end
