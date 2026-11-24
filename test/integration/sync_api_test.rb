require "test_helper"

class SyncApiTest < ActionDispatch::IntegrationTest
  test "the manifest lists the book and its active leaves in position order" do
    get book_manifest_url(books(:handbook), format: :json), headers: bearer_headers
    assert_response :success

    manifest = response.parsed_body
    assert_equal "Handbook", manifest["book"]["title"]
    assert_equal books(:handbook).fingerprint, manifest["book"]["fingerprint"]

    leaves = manifest["leaves"]
    assert_equal %w[ Section Page Page Picture ], leaves.map { it["type"] }
    assert_equal leaves(:welcome_page).fingerprint, leaves.second["fingerprint"]
    assert_equal "reading.webp", leaves.fourth["image"]["filename"]
  end

  test "trashed leaves are left out of the manifest" do
    leaves(:summary_page).trashed!

    get book_manifest_url(books(:handbook), format: :json), headers: bearer_headers
    assert_not_includes response.parsed_body["leaves"].map { it["id"] }, leaves(:summary_page).id
  end

  test "showing a page returns its raw markdown and an upload gid" do
    get book_page_url(books(:handbook), leaves(:welcome_page), format: :json), headers: bearer_headers
    assert_response :success

    page = response.parsed_body
    assert_equal "This is _such_ a great handbook.", page["body"]
    assert_equal leaves(:welcome_page).fingerprint, page["fingerprint"]
    assert page["record_gid"].present?
  end

  test "creating a page at a position" do
    assert_difference -> { books(:handbook).leaves.active.count }, +1 do
      post book_pages_url(books(:handbook), format: :json), headers: bearer_headers,
        params: { leaf: { title: "Epilogue" }, page: { body: "The end." }, position: 1 }
    end

    assert_response :created

    created = response.parsed_body
    leaf = Leaf.find(created["id"])
    assert_equal "Epilogue", leaf.title
    assert_equal "The end.", leaf.leafable.markable
    assert_equal leaf, books(:handbook).leaves.active.positioned.second
  end

  test "updating a page with the current fingerprint succeeds and returns the new one" do
    leaf = leaves(:welcome_page)

    patch book_page_url(books(:handbook), leaf, format: :json), headers: bearer_headers,
      params: { leaf: { title: "Welcome!" }, page: { body: "Fresh words." }, base_fingerprint: leaf.fingerprint }

    assert_response :success
    assert_equal "Fresh words.", leaf.reload.leafable.markable
    assert_equal leaf.fingerprint, response.parsed_body["fingerprint"]
  end

  test "updating with a stale fingerprint answers 409 and changes nothing" do
    leaf = leaves(:welcome_page)

    patch book_page_url(books(:handbook), leaf, format: :json), headers: bearer_headers,
      params: { leaf: { title: "Clobbered" }, page: { body: "Clobbered." }, base_fingerprint: "stale" }

    assert_response :conflict
    assert_equal "stale_write", response.parsed_body["error"]
    assert_equal leaf.fingerprint, response.parsed_body["fingerprint"]
    assert_equal "Welcome to The Handbook!", leaf.reload.title
  end

  test "updates without a base fingerprint keep last-write-wins for the web editor" do
    leaf = leaves(:welcome_page)

    patch book_page_url(books(:handbook), leaf, format: :json), headers: bearer_headers,
      params: { leaf: { title: "No guard" }, page: { body: "Still fine." } }

    assert_response :success
    assert_equal "No guard", leaf.reload.title
  end

  test "destroying a leaf trashes it" do
    delete book_page_url(books(:handbook), leaves(:summary_page), format: :json), headers: bearer_headers

    assert_response :no_content
    assert leaves(:summary_page).reload.trashed?
  end

  test "one moves call reorders the whole book" do
    book = books(:handbook)
    reversed = book.leaves.active.positioned.reverse

    post book_leaves_moves_url(book, format: :json), headers: bearer_headers,
      params: { id: reversed.map(&:id), position: 0 }

    assert_response :no_content
    assert_equal reversed.map(&:id), book.leaves.active.positioned.map(&:id)
  end

  test "updating the book's metadata returns its new fingerprint" do
    patch book_url(books(:handbook), format: :json), headers: bearer_headers,
      params: { book: { title: "The Handbook", author: "David" } }

    assert_response :success
    assert_equal "The Handbook", books(:handbook).reload.title
    assert_equal books(:handbook).fingerprint, response.parsed_body["fingerprint"]
  end

  test "readers can fetch the manifest but not write" do
    get book_manifest_url(books(:handbook), format: :json), headers: bearer_headers(JZS_ACCESS_TOKEN)
    assert_response :success

    patch book_page_url(books(:handbook), leaves(:welcome_page), format: :json),
      headers: bearer_headers(JZS_ACCESS_TOKEN),
      params: { leaf: { title: "Nope" }, page: { body: "Nope." } }
    assert_response :forbidden
    assert_equal "Welcome to The Handbook!", leaves(:welcome_page).reload.title
  end
end
