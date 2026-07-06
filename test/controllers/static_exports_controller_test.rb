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
end