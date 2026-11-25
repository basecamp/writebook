require "test_helper"

class BooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :kevin
  end

  test "index lists the current user's books" do
    get root_url

    assert_response :success
    assert_select "h2", text: "Handbook"
    assert_select "h2", text: "Manual", count: 0
  end

  test "index includes published books, even when the user does not have access" do
    books(:manual).update!(published: true)

    get root_url

    assert_response :success
    assert_select "h2", text: "Handbook"
    assert_select "h2", text: "Manual"
  end

  test "index shows published books when not logged in" do
    books(:manual).update!(published: true)

    sign_out
    get root_url

    assert_response :success
    assert_select "h2", text: "Handbook", count: 0
    assert_select "h2", text: "Manual"
  end

  test "index lists the readable books as JSON, with links to read and search them" do
    books(:manual).update!(published: true)

    get books_path(format: :json)

    assert_response :success
    assert_equal %w[ Handbook Manual ], response.parsed_body.map { it["title"] }

    handbook = response.parsed_body.first
    assert_equal books(:handbook).id, handbook["id"]
    assert_equal book_slug_url(books(:handbook), format: :md), handbook["markdown_url"]
    assert_equal book_manifest_url(books(:handbook), format: :json), handbook["manifest_url"]
    assert_equal book_search_url(books(:handbook), format: :json), handbook["search_url"]
  end

  test "index JSON includes the theme, the cover and whether the user can edit each book" do
    books(:handbook).cover.attach io: file_fixture("reading.webp").open, filename: "reading.webp"

    get books_path(format: :json)

    handbook = response.parsed_body.first
    assert_equal "blue", handbook["theme"]
    assert_equal true, handbook["editable"]
    assert_equal books(:handbook).cover.blob.checksum, handbook["cover"]["checksum"]
    assert_equal rails_blob_path(books(:handbook).cover), handbook["cover"]["url"]

    sign_in :jz
    books(:handbook).cover.purge

    get books_path(format: :json)

    handbook = response.parsed_body.first
    assert_equal false, handbook["editable"]
    assert_nil handbook["cover"]
  end

  test "index JSON marks published books as not editable when nobody is signed in" do
    sign_out
    books(:handbook).update!(published: true)

    get books_path(format: :json)

    assert_equal [ false ], response.parsed_body.map { it["editable"] }
  end

  test "index JSON answers an empty list when nobody is signed in and nothing is published" do
    sign_out

    get books_path(format: :json)

    assert_response :success
    assert_equal [], response.parsed_body
  end

  test "index JSON leaves out books the user can't read" do
    sign_in :kevin

    get books_path(format: :json)

    assert_equal %w[ Handbook ], response.parsed_body.map { it["title"] }
  end

  test "index redirects to login if not signed in and no published books exist" do
    sign_out
    get root_url

    assert_redirected_to new_session_url
  end

  test "create makes the current user an editor" do
    assert_difference -> { Book.count }, +1 do
      post books_url, params: { book: { title: "New Book", everyone_access: false } }
    end

    assert_redirected_to book_slug_url(Book.last)

    book = Book.last
    assert_equal "New Book", book.title
    assert_equal 1, Book.last.accesses.count

    assert book.editable?(user: users(:kevin))
  end

  test "create sets additional accesses" do
    sign_in :jason
    assert_difference -> { Book.count }, +1 do
      post books_url, params: { book: { title: "New Book", everyone_access: false }, "editor_ids[]": users(:jz).id, "reader_ids[]": users(:kevin).id }
    end

    book = Book.last
    assert_equal "New Book", book.title
    assert_equal 3, Book.last.accesses.count

    assert book.editable?(user: users(:jz))

    assert book.accessable?(user: users(:kevin))
    assert_not book.editable?(user: users(:kevin))
  end

  test "show only shows books the current user can access" do
    get book_slug_url(books(:manual))
    assert_response :not_found

    get book_slug_url(books(:handbook))
    assert_response :success
  end

  test "show includes OG metadata for public access" do
    get book_slug_url(books(:handbook))
    assert_response :success

    assert_select "meta[property='og:title'][content='Handbook']"
    assert_select "meta[property='og:url'][content='#{book_slug_url(books(:handbook))}']"
  end

  test "show with markdown format returns combined markables" do
    leaves(:welcome_page).leafable.update!(body: "# Welcome Content")
    leaves(:summary_page).leafable.update!(body: "# Summary Content")

    get book_slug_path(books(:handbook), format: :md)

    assert_response :success
    assert_in_body "# Welcome Content"
    assert_in_body "# Summary Content"
  end

  test "show with markdown format does not escape HTML" do
    leaves(:welcome_page).leafable.update!(body: "<div class='test'>HTML content</div>")

    get book_slug_path(books(:handbook), format: :md)

    assert_response :success
    assert_in_body "<div class='test'>"
    assert_not_in_body "&lt;"
  end

  test "show re-scrubs cached leaves when an allowlist is configured over permissive embeds" do
    with_fragment_caching do
      leaves(:welcome_page).leafable.update!(body: %(<iframe src="https://x.example/embed/1"></iframe>))

      writes = 0
      ActiveSupport::Notifications.subscribed(->(*) { writes += 1 }, "write_fragment.action_controller") do
        get book_slug_path(books(:handbook))
      end
      assert_response :success
      assert_select "iframe[src=?]", "https://x.example/embed/1"
      assert_operator writes, :>, 0, "expected the page to be fragment cached"

      ENV["WRITEBOOK_EMBED_PROVIDERS"] = EmbedProvider::DEFAULTS.to_json
      get book_slug_path(books(:handbook))
      assert_response :success
      assert_select "iframe", count: 0
    end
  end

  test "show re-scrubs cached leaves when the allowlist narrows" do
    with_fragment_caching do
      leaves(:welcome_page).leafable.update!(body: %(<iframe src="https://x.example/embed/1"></iframe>))

      ENV["WRITEBOOK_EMBED_PROVIDERS"] = %([{"hosts":["x.example"],"path_prefix":"/embed"}])
      get book_slug_path(books(:handbook))
      assert_select "iframe[src=?]", "https://x.example/embed/1"

      ENV["WRITEBOOK_EMBED_PROVIDERS"] = EmbedProvider::DEFAULTS.to_json
      get book_slug_path(books(:handbook))
      assert_select "iframe", count: 0
    end
  end

  test "show includes link to markdown format" do
    get book_slug_path(books(:handbook))

    assert_response :success
    assert_select "link[rel=\"alternate\"][type=\"text/markdown\"][href=\"#{book_slug_path(books(:handbook), format: :md)}\"]"
  end

  test "new JSON describes a blank book and who would get access to it" do
    get new_book_path(format: :json)

    assert_response :success
    assert_equal({ "id" => nil, "title" => nil, "subtitle" => nil, "author" => nil, "theme" => "blue", "everyone_access" => true, "cover" => nil }, response.parsed_body["book"])
    assert_equal [
      { "id" => users(:david).id, "name" => "David", "role" => "editor", "administrator" => true, "current" => false },
      { "id" => users(:jz).id, "name" => "JZ", "role" => "none", "administrator" => false, "current" => false },
      { "id" => users(:jason).id, "name" => "Jason", "role" => "editor", "administrator" => true, "current" => false },
      { "id" => users(:kevin).id, "name" => "Kevin", "role" => "editor", "administrator" => false, "current" => true }
    ], response.parsed_body["users"]
  end

  test "edit JSON describes the book and each user's access to it" do
    books(:handbook).update!(subtitle: "For everyone", author: "37signals", theme: "green", everyone_access: false)
    books(:handbook).cover.attach io: file_fixture("reading.webp").open, filename: "reading.webp"

    get edit_book_path(books(:handbook), format: :json)

    assert_response :success
    assert_equal({
      "id" => books(:handbook).id, "title" => "Handbook", "subtitle" => "For everyone", "author" => "37signals", "theme" => "green", "everyone_access" => false,
      "cover" => { "checksum" => books(:handbook).cover.blob.checksum, "url" => rails_blob_path(books(:handbook).cover) }
    }, response.parsed_body["book"])
    assert_equal %w[ editor reader editor editor ], response.parsed_body["users"].map { it["role"] }
    assert_equal [ users(:kevin).id ], response.parsed_body["users"].select { it["current"] }.map { it["id"] }

    sign_in :david
    get edit_book_path(books(:manual), format: :json)

    assert_equal({ "David" => "editor", "Jason" => "editor", "JZ" => "reader", "Kevin" => "none" }, response.parsed_body["users"].to_h { [ it["name"], it["role"] ] })
  end

  test "edit JSON is forbidden to readers" do
    sign_in :jz
    get edit_book_path(books(:handbook), format: :json)

    assert_response :forbidden
  end

  test "create JSON makes the book with its cover and accesses" do
    sign_in :jason

    assert_difference -> { Book.count }, +1 do
      post books_path(format: :json), params: {
        book: { title: "New Book", everyone_access: false, cover: fixture_file_upload("reading.webp", "image/webp") },
        editor_ids: [ users(:jz).id ], reader_ids: [ users(:kevin).id ]
      }
    end

    book = Book.last
    assert_response :created
    assert_equal({ "id" => book.id, "slug" => "new-book", "url" => book_slug_url(book), "fingerprint" => book.fingerprint }, response.parsed_body)
    assert book.cover.attached?
    assert_equal({ users(:jason) => "editor", users(:jz) => "editor", users(:kevin) => "reader" }, book.accesses.to_h { [ it.user, it.level ] })
  end

  test "update JSON changes accesses when they're given" do
    books(:handbook).update!(everyone_access: false)

    patch book_path(books(:handbook), format: :json), params: { editor_ids: [ users(:jz).id ], reader_ids: [ users(:david).id ] }, as: :json

    assert_response :success
    assert_equal({ users(:david) => "reader", users(:jz) => "editor", users(:kevin) => "editor" }, books(:handbook).accesses.to_h { [ it.user, it.level ] })

    patch book_path(books(:handbook), format: :json), params: { editor_ids: [], reader_ids: [] }, as: :json

    assert_response :success
    assert_equal({ users(:kevin) => "editor" }, books(:handbook).accesses.reload.to_h { [ it.user, it.level ] })
  end

  test "update JSON leaves accesses alone when none are given" do
    assert_no_changes -> { books(:handbook).accesses.pluck(:user_id, :level).sort } do
      patch book_path(books(:handbook), format: :json), params: { book: { title: "Changed", everyone_access: false } }, as: :json
    end

    assert_response :success
    assert_equal "Changed", books(:handbook).reload.title
  end

  test "destroy redirects for HTML and answers No Content for JSON" do
    delete book_path(books(:handbook))

    assert_redirected_to root_url
    assert_not Book.exists?(books(:handbook).id)

    sign_in :david
    delete book_path(books(:manual), format: :json)

    assert_response :no_content
    assert_not Book.exists?(books(:manual).id)
  end

  private
    def with_fragment_caching
      perform_caching, cache_store = ActionController::Base.perform_caching, ActionController::Base.cache_store
      ActionController::Base.perform_caching = true
      ActionController::Base.cache_store = :memory_store
      yield
    ensure
      ActionController::Base.perform_caching = perform_caching
      ActionController::Base.cache_store = cache_store
    end
end
