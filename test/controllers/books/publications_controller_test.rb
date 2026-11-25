require "test_helper"

class Books::PublicationsTest < ActionDispatch::IntegrationTest
  setup do
    @book = books(:manual)

    sign_in :david
  end

  test "publish a book" do
    assert_changes -> { @book.reload.published? }, from: false, to: true do
      patch book_publication_url(@book), params: { book: { published: "1" } }
    end

    @book.reload
    assert_redirected_to book_slug_url(@book)
    assert_equal "manual", @book.slug
  end

  test "edit book slug" do
    @book.update! published: true

    get edit_book_publication_url(@book)
    assert_response :success

    patch book_publication_url(@book), params: { book: { slug: "new-slug" } }

    @book.reload
    assert_redirected_to book_slug_url(@book)
    assert_equal "new-slug", @book.slug
  end

  test "publish a book as JSON with a full-access token" do
    sign_out

    patch book_publication_url(@book, format: :json), params: { book: { published: "1", slug: "the-manual" } }, headers: bearer_headers
    assert_response :success

    assert @book.reload.published?
    assert_equal({ "published" => true, "slug" => "the-manual", "url" => book_slug_url(@book) }, response.parsed_body)
  end

  test "a read-only token can't publish a book" do
    sign_out

    assert_no_changes -> { books(:handbook).reload.published? } do
      patch book_publication_url(books(:handbook), format: :json), params: { book: { published: "1" } }, headers: bearer_headers(KEVINS_READ_ONLY_ACCESS_TOKEN)
    end
    assert_response :forbidden
  end
end
