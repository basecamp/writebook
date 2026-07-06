require "test_helper"

class StaticExportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    # The exporter renders Book.published; publish the fixture book so the
    # generated site has something in it. Start from a clean output dir.
    books(:handbook).update!(published: true)
    FileUtils.rm_rf(Rails.root.join("tmp/static-site"))
  end

  teardown { FileUtils.rm_rf(Rails.root.join("tmp/static-site")) }

  test "show requires authentication" do
    get static_export_url
    assert_redirected_to new_session_url
  end

  test "create requires authentication" do
    post static_export_url
    assert_redirected_to new_session_url
  end

  test "non-admins are forbidden" do
    sign_in :kevin
    assert users(:kevin).member?

    get static_export_url
    assert_response :forbidden

    post static_export_url
    assert_response :forbidden

    get static_export_download_url
    assert_response :forbidden

    get static_site_preview_url
    assert_response :forbidden

    get static_export_result_url
    assert_response :forbidden
  end

  test "download and preview require authentication" do
    get static_export_download_url
    assert_redirected_to new_session_url

    get static_site_preview_url
    assert_redirected_to new_session_url
  end

  test "admin download streams a zip of the generated site" do
    sign_in :david

    get static_export_download_url
    assert_response :ok
    assert_match %r{application/zip}, response.content_type.to_s
    assert_match "PK", response.body # local-part of a zip file
  end

  test "admin preview serves the generated index" do
    sign_in :david

    get static_site_preview_url
    assert_response :ok
    assert_match %r{text/html}, response.content_type.to_s
    assert_match books(:handbook).title, response.body
  end

  test "admin create with no published books renders the nothing-to-export page" do
    sign_in :david
    Book.update_all(published: false)

    post static_export_url
    assert_redirected_to static_export_result_url
    follow_redirect!
    assert_response :ok
    assert_match "Nothing to export", response.body
    assert_no_match "Your static site is ready", response.body
  end

  test "admin create with no books at all renders empty even with drafts requested" do
    sign_in :david
    Book.destroy_all

    post static_export_url, params: { include_drafts: "1" }
    assert_redirected_to static_export_result_url
    follow_redirect!
    assert_response :ok
    assert_match "Nothing to export", response.body
  end

  test "admin create with drafts exports unpublished books and leaves the DB untouched" do
    sign_in :david
    books(:handbook).update!(published: false) # nothing published; handbook is now a draft

    post static_export_url, params: { include_drafts: "1" }
    assert_redirected_to static_export_result_url
    follow_redirect!
    assert_response :ok
    assert_match "Your static site is ready", response.body

    dir = Rails.root.join("tmp/static-site")
    book = books(:handbook)
    assert File.exist?(dir.join(book.id.to_s, book.slug, "index.html")),
      "the unpublished draft should have been exported"

    assert_equal false, Book.find(book.id).published,
      "the live database must be left untouched (draft still unpublished after rollback)"
  end

  test "admin show renders the landing page" do
    sign_in :david
    assert users(:david).administrator?

    get static_export_url
    assert_response :ok
    assert_match "Generate static site", @response.body
  end

  test "admin create renders the static site and the result page" do
    sign_in :david

    post static_export_url
    assert_redirected_to static_export_result_url
    follow_redirect!
    assert_response :ok

    dir = Rails.root.join("tmp/static-site")
    assert File.exist?(dir.join("index.html")), "expected the library index"

    book = books(:handbook)
    # The .md alternate routes are rendered too, so the alternate links resolve
    # instead of 404ing on the static host.
    assert File.exist?(dir.join(book.id.to_s, "#{book.slug}.md")),
      "expected the book markdown alternate"
    leaf = book.leaves.active.with_leafables.positioned.first
    assert File.exist?(dir.join(book.id.to_s, book.slug, leaf.id.to_s, "#{leaf.slug}.md")),
      "expected the leaf markdown alternate"

    assert_match "Your static site is ready", @response.body
    assert_match "Preview locally", @response.body
  end

  test "admin result without a stashed export falls back to the landing page" do
    sign_in :david

    get static_export_result_url
    assert_redirected_to static_export_url
  end

  test "result requires authentication" do
    get static_export_result_url
    assert_redirected_to new_session_url
  end
end