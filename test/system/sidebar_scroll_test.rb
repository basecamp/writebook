require "application_system_test_case"

class SidebarScrollTest < ApplicationSystemTestCase
  setup do
    sign_in "kevin@example.com"

    leaves(:welcome_page).leafable.update! body: ([ "A paragraph of the book." ] * 400).join("\n\n")

    visit leafable_slug_path(leaves(:welcome_page))
    find("label.sidebar__toggle").click

    assert_operator document_height, :>, viewport_height * 2,
      "the test page should be considerably taller than the viewport"
  end

  test "the table of contents fits the viewport instead of the page" do
    assert_operator sidebar_height, :<=, viewport_height,
      "the sidebar is #{sidebar_height}px tall in a #{viewport_height}px viewport: " \
      "it grows with the length of the page instead of staying within the screen"
  end

  test "the table of contents stays put while the page scrolls" do
    execute_script "window.scrollTo(0, document.documentElement.scrollHeight)"

    assert_equal 0, sidebar_top.round,
      "the sidebar scrolled away with the page instead of staying in view"
  end

  private
    def viewport_height = evaluate_script("window.innerHeight")

    def document_height = evaluate_script("document.documentElement.scrollHeight")

    def sidebar_height = sidebar_rect["height"]

    def sidebar_top = sidebar_rect["top"]

    def sidebar_rect
      evaluate_script("document.querySelector('#sidebar').getBoundingClientRect().toJSON()")
    end
end
