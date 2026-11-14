require "application_interaction_test_case"

class PublishTest < ApplicationInteractionTestCase
  setup do
    sign_in "kevin@example.com"
  end

  test "create and publish a book" do
    visit new_book_url

    fill_in "Book title", with: "My Book of Jokes"
    fill_in "Author", with: "Kevin"
    within "footer" do
      click_button
    end

    assert_text "My Book of Jokes"

    click_on "Add a new section page"
    fill_in "leaf_title", with: "A horse walks into a bar"
    click_on "Save"

    click_on "Add a new section page"
    fill_in "leaf_title", with: "And the barman says 'Why the long face?'"
    click_on "Save"

    find(class: "switch__btn").click
    public_url = find(id: "invite_url").value

    using_session "public" do
      visit public_url
      assert_text "My Book of Jokes"

      page.send_keys :arrow_right
      assert_text "A horse walks into a bar"
    end
  end
end
