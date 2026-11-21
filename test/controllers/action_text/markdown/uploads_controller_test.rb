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

    # Uploads should use relative URLs, to allow for future hostname changes
    assert JSON.parse(response.body)["fileUrl"].start_with?("/")
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

  test "an upload must be a file, not the signed id of another book's file" do
    books(:manual).cover.attach \
      io: file_fixture("reading.webp").open, filename: "reading.webp", content_type: "image/webp"
    cover = books(:manual).cover.blob

    assert_no_changes -> { ActiveStorage::Attachment.count } do
      post action_text_markdown_uploads_url, params: {
        record_gid: uploads_signed_id_for(pages(:welcome)),
        attribute_name: "body",
        file: cover.signed_id
      }, as: :xhr
    end

    assert_response :unprocessable_entity
    assert_equal [ books(:manual) ], ActiveStorage::Attachment.where(blob: cover).map(&:record)
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

  test "a publicly cached redirect doesn't take its host from X-Forwarded-Host" do
    books(:handbook).update! published: true
    attachment = attach_upload_to_welcome_page

    reset!
    get action_text_markdown_upload_path(slug: attachment.slug), headers: { "X-Forwarded-Host" => "attacker.example" }

    assert_response :found
    assert_match "public", response.headers["Cache-Control"]
    assert_match %r{\A/rails/active_storage/disk/.*/reading\.webp\z}, response.headers["Location"]
    assert_not_includes response.headers["Location"], "attacker.example"
  end

  test "a publicly cached redirect doesn't take its host from the Host header" do
    books(:handbook).update! published: true
    attachment = attach_upload_to_welcome_page

    reset!
    host! "attacker.example"
    get action_text_markdown_upload_path(slug: attachment.slug)

    assert_response :found
    assert_match "public", response.headers["Cache-Control"]
    assert response.headers["Location"].start_with?("/rails/active_storage/disk/")
  end

  test "a privately cached redirect is path-only too" do
    books(:handbook).update! published: false
    attachment = attach_upload_to_welcome_page

    sign_in :jz
    get action_text_markdown_upload_path(slug: attachment.slug), headers: { "X-Forwarded-Host" => "attacker.example" }

    assert_response :found
    assert_match "private", response.headers["Cache-Control"]
    assert response.headers["Location"].start_with?("/rails/active_storage/disk/")
  end

  test "the path-only redirect serves the attached file" do
    books(:handbook).update! published: true
    attachment = attach_upload_to_welcome_page

    reset!
    get action_text_markdown_upload_path(slug: attachment.slug)
    get response.headers["Location"]

    assert_response :success
    assert_equal file_fixture("reading.webp").binread, response.body
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

  test "an attachment whose owning book can't be resolved is not served" do
    books(:handbook).update! published: false
    attachment = attach_upload_to_welcome_page

    # Sever the leaf without cascading the destroy, leaving the attachment live but
    # its owning book unresolvable. The guard must fail closed on the nil book.
    pages(:welcome).leaf.delete
    assert_nil pages(:welcome).reload.owning_book

    reset!
    get action_text_markdown_upload_path(slug: attachment.slug)

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
