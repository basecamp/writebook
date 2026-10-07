require "application_system_test_case"

class BookCoverTest < ApplicationSystemTestCase
  setup do
    sign_in "kevin@example.com"
  end

  test "upload a cover, and keep it when the book is edited without choosing another" do
    visit new_book_url

    fill_in "Book title", with: "Covered"
    attach_file "book[cover]", file_fixture("reading.webp"), make_visible: true
    within "footer" do
      click_button
    end

    assert_selector "img[alt='Cover for Covered']"
    assert_equal "reading.webp", Book.find_by!(title: "Covered").cover.filename.to_s

    visit edit_book_url(Book.find_by!(title: "Covered"))
    fill_in "Book title", with: "Still covered"
    click_button "Save changes"

    assert_selector "img[alt='Cover for Still covered']"
    assert Book.find_by!(title: "Still covered").cover.attached?
  end
end
