require "application_interaction_test_case"

class EditPageTest < ApplicationInteractionTestCase
  setup do
    sign_in "kevin@example.com"
  end

  test "edit page" do
    visit edit_book_page_url(books(:handbook), leaves(:welcome_page))
    assert_selector "house-md"

    fill_house_editor "page[body]", "Welcome to the handbook! This is the **first** page."

    click_button "Save"

    assert_selector ".house-md-content", text: "Welcome to the handbook! This is the **first** page."
    assert_selector ".house-md-content strong", text: "first"
    assert_selector "form#leafable-editor.clean"
    assert_equal "Welcome to the handbook! This is the **first** page.", leaves(:welcome_page).reload.leafable.body.content.to_s
  end
end
