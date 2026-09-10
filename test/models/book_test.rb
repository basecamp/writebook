require "test_helper"

class BookTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "slug is generated from title" do
    book = Book.create!(title: "Hello, World!")
    assert_equal "hello-world", book.slug
  end

  test "press a leafable" do
    leaf = books(:manual).press Page.new(body: "Important words"), title: "Introduction"

    assert leaf.page?
    assert_equal "Important words", leaf.page.body.content.to_s
    assert_equal "Introduction", leaf.title
  end

  test "markable combines all leafables" do
    leaves(:welcome_page).leafable.update!(body: "Welcome page content")
    leaves(:summary_page).leafable.update!(body: "Summary page content")

    assert_includes books(:handbook).markable, "Welcome page content"
    assert_includes books(:handbook).markable, "Summary page content"
  end

  test "markable joins leafables with double newlines" do
    leaves(:welcome_page).leafable.update!(body: "Welcome content")
    leaves(:summary_page).leafable.update!(body: "Summary content")

    assert_includes books(:handbook).markable, "Welcome content\n\nSummary content"
  end

  test "markable only includes active leaves" do
    leaves(:welcome_page).leafable.update!(body: "Active content")
    leaves(:summary_page).trashed!

    assert_includes books(:handbook).markable, "Active content"
    assert_not_includes books(:handbook).markable, leaves(:summary_page).title
  end

  test "markable returns empty string for book with no leaves" do
    assert_equal "", books(:manual).markable
  end

  test "destroying a book removes superseded revisions along with their content and files" do
    page = leaves(:welcome_page).page
    page.body.uploads.attach io: file_fixture("pixel.bmp").open, filename: "pixel.bmp", content_type: "image/bmp"
    upload_blob = page.body.uploads.blobs.sole
    leaves(:welcome_page).edit leafable_params: { body: "Revised body" }

    picture = leaves(:reading_picture).picture
    image_blob = picture.image.blob
    leaves(:reading_picture).edit leafable_params: { caption: "Revised caption" }

    assert_equal page, leaves(:welcome_page).edits.revision.sole.leafable
    assert_equal picture, leaves(:reading_picture).edits.revision.sole.leafable

    perform_enqueued_jobs do
      books(:handbook).destroy
    end

    assert_not Edit.exists?(leaf_id: leaves(:welcome_page, :reading_picture).map(&:id))
    assert_not Page.exists?(page.id)
    assert_not ActionText::Markdown.exists?(record: page)
    assert_not Picture.exists?(picture.id)
    assert_not ActiveStorage::Attachment.exists?(blob: [ upload_blob, image_blob ])
    assert_not ActiveStorage::Blob.exists?(upload_blob.id)
    assert_not ActiveStorage::Blob.exists?(image_blob.id)
    assert_not ActiveStorage::Blob.service.exist?(upload_blob.key)
    assert_not ActiveStorage::Blob.service.exist?(image_blob.key)
  end

  test "destroying a book removes the content a trashed leaf shares with its trash edit" do
    page = leaves(:welcome_page).page
    leaves(:welcome_page).trashed!

    assert_equal page, leaves(:welcome_page).edits.trash.sole.leafable

    books(:handbook).destroy

    assert_not Leaf.exists?(leaves(:welcome_page).id)
    assert_not Edit.exists?(leaf_id: leaves(:welcome_page).id)
    assert_not Page.exists?(page.id)
    assert_not ActionText::Markdown.exists?(record: page)
  end
end
