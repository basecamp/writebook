require "test_helper"

class Books::SearchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :kevin

    Leaf.reindex_all
  end

  test "create finds matching pages" do
    post book_search_url(books(:handbook)), params: { search: "Thanks" }

    assert_response :success
    assert_select "a", text: /Thanks for reading/i
  end

  test "create allows searching published books without being logged in" do
    sign_out
    books(:handbook).update!(published: true)

    post book_search_url(books(:handbook)), params: { search: "Thanks" }
    assert_response :success

    books(:handbook).update!(published: false)

    post book_search_url(books(:handbook)), params: { search: "Thanks" }
    assert_response :not_found
  end

  test "create shows when there are no matches" do
    post book_search_url(books(:handbook)), params: { search: "the invisible man" }

    assert_response :success
    assert_select "p", text: /no matches/i
  end

  test "create shows no matches when the search has only ignored characters" do
    post book_search_url(books(:handbook)), params: { search: "^$" }

    assert_response :success
    assert_select "p", text: /no matches/i
  end

  test "create does not find trashed pages" do
    leaves(:summary_page).trashed!

    post book_search_url(books(:handbook)), params: { search: "Thanks" }

    assert_response :success
    assert_select "p", text: /no matches/i
  end

  test "search results strip dangerous tags from section body" do
    section = Section.new(body: 'findme <img src=x onerror="alert(1)">')
    books(:handbook).press(section, title: "Safe Title")
    section.leaf.reindex

    post book_search_url(books(:handbook)), params: { search: "findme" }

    assert_response :success
    assert_select "a.search__result", count: 2 do |results|
      results.each do |result|
        assert_pattern {
          result => {
            elements: [
              { name: "strong", content: "Safe Title:" },
              { name: "mark", content: "findme" }
            ]
          }
        }
      end
    end
  end

  test "search results strip dangerous tags from section title" do
    section = Section.new(body: "findme content")
    books(:handbook).press(section, title: 'findme <img src=x onerror="alert(1)">')
    section.leaf.reindex

    post book_search_url(books(:handbook)), params: { search: "findme" }

    assert_response :success
    assert_select "a.search__result", count: 2 do |results|
      results.each do |result|
        assert_pattern {
          result => {
            elements: [
              { name: "strong", elements: [{ name: "mark", content: "findme" }] },
              { name: "mark", content: "findme" }
            ]
          }
        }
      end
    end
  end

  test "search results strip dangerous tags from page body" do
    pages(:welcome).update! body: 'findme <b>bold</b>'
    leaves(:welcome_page).reindex

    post book_search_url(books(:handbook)), params: { search: "findme" }

    assert_response :success
    assert_select "a.search__result", count: 2 do |results|
      results.each do |result|
        assert_pattern {
          result => {
            elements: [
              { name: "strong", content: /Handbook/ },
              { name: "mark", content: "findme" }
            ]
          }
        }
      end
    end
  end

  test "search results strip dangerous tags from page title" do
    leaf = leaves(:welcome_page)
    leaf.update! title: 'findme <b>bold</b>'
    leaf.reindex

    post book_search_url(books(:handbook)), params: { search: "findme" }

    assert_response :success
    assert_select "a.search__result", count: 2 do |results|
      results.each do |result|
        assert_pattern {
          result => {
            elements: [
              { name: "strong", elements: [{ name: "mark", content: "findme" }], content: "findme bold:" }
            ]
          }
        }
      end
    end
  end

  test "search results encode entities in section body" do
    section = Section.new(body: "findme Tom & Jerry")
    books(:handbook).press(section, title: "Safe Title")
    section.leaf.reindex

    post book_search_url(books(:handbook)), params: { search: "findme" }

    assert_response :success
    assert_includes response.body, "Tom &amp; Jerry"
  end

  test "search results encode entities in section title" do
    section = Section.new(body: "findme content")
    books(:handbook).press(section, title: "findme Tom & Jerry")
    section.leaf.reindex

    post book_search_url(books(:handbook)), params: { search: "findme" }

    assert_response :success
    assert_includes response.body, "Tom &amp; Jerry"
  end

  test "search results encode entities in page body" do
    pages(:welcome).update! body: "findme Tom & Jerry"
    leaves(:welcome_page).reindex

    post book_search_url(books(:handbook)), params: { search: "findme" }

    assert_response :success
    assert_includes response.body, "Tom &amp; Jerry"
  end

  test "search results encode entities in page title" do
    leaf = leaves(:welcome_page)
    leaf.update! title: "findme Tom & Jerry"
    leaf.reindex

    post book_search_url(books(:handbook)), params: { search: "findme" }

    assert_response :success
    assert_includes response.body, "Tom &amp; Jerry"
  end

  test "search results sanitize pre-existing poisoned body in the index" do
    section = Section.new(body: "findme safe content")
    books(:handbook).press(section, title: "Safe Title")

    Leaf.connection.execute(
      Leaf.sanitize_sql([
        "update leaf_search_index set content = ? where rowid = ?",
        'findme <img src=x onerror="alert(1)"> Tom & Jerry', section.leaf.id
      ])
    )

    post book_search_url(books(:handbook)), params: { search: "findme" }

    assert_response :success
    assert_select "a.search__result", count: 2 do |results|
      results.each do |result|
        assert_pattern {
          result => {
            elements: [
              { name: "strong", content: "Safe Title:" },
              { name: "mark", content: "findme" }
            ]
          }
        }
      end
    end
    assert_includes response.body, "Tom &amp; Jerry"
  end

  test "search results sanitize pre-existing poisoned title in the index" do
    section = Section.new(body: "findme safe content")
    books(:handbook).press(section, title: "Safe Title")

    Leaf.connection.execute(
      Leaf.sanitize_sql([
        "update leaf_search_index set title = ? where rowid = ?",
        'findme <mark onclick="alert(1)">fake</mark> <img src=x onerror="alert(1)">', section.leaf.id
      ])
    )

    post book_search_url(books(:handbook)), params: { search: "findme" }

    assert_response :success
    assert_select "a.search__result", count: 2 do |results|
      results.each do |result|
        assert_pattern {
          result => {
            elements: [
              {
                name: "strong",
                elements: [
                  { name: "mark", content: "findme", attributes: [] },
                  { name: "mark", content: "fake", attributes: [] }
                ]
              },
              { name: "mark", content: "findme" }
            ]
          }
        }
      end
    end
  end
end
