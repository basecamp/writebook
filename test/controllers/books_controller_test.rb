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

  test "show includes link to markdown format" do
    get book_slug_path(books(:handbook))

    assert_response :success
    assert_select "link[rel=\"alternate\"][type=\"text/markdown\"][href=\"#{book_slug_path(books(:handbook), format: :md)}\"]"
  end

  test "update persists view settings" do
    book = books(:handbook)

    patch book_path(book), params: { book: { default_view: "list", allow_view_selector: false } }

    assert_redirected_to book_slug_path(book)
    book.reload
    assert_equal "list", book.default_view
    assert_not book.allow_view_selector?
  end

  test "show hides view selector when disabled" do
    book = books(:handbook)
    book.update!(allow_view_selector: false)

    get book_slug_path(book)

    assert_response :success
    assert_not_in_body "List view"
    assert_not_in_body "Page view"
    assert_not_in_body "view-list"
    assert_not_in_body "view-grid"
  end

  test "show applies forced view class when selector is disabled" do
    book = books(:handbook)
    book.update!(allow_view_selector: false, default_view: "list")

    get book_slug_path(book)

    assert_response :success
    assert_in_body "toc__container--force-list"
  end

  test "show shows view selector when enabled" do
    book = books(:handbook)
    book.update!(allow_view_selector: true)

    get book_slug_path(book)

    assert_response :success
    assert_in_body "List view"
    assert_in_body "Page view"
  end
end
