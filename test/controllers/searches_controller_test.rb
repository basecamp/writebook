require "test_helper"

class SearchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :kevin

    Leaf.reindex_all
  end

  test "show searches every book the user can read and answers JSON" do
    get search_path(format: :json, q: "Thanks")

    assert_response :success
    assert_equal "Thanks", response.parsed_body["query"]

    result = response.parsed_body["results"].sole
    assert_equal leaves(:summary_page).id, result["id"]
    assert_equal "Summary", result["title"]
    assert_equal "Page", result["type"]
    assert_equal({ "id" => books(:handbook).id, "title" => "Handbook" }, result["book"])
    assert_equal leafable_slug_url(leaves(:summary_page), format: :md), result["markdown_url"]
    assert_equal "Thanks for reading!", result["snippet"]
  end

  test "show leaves out books the user can't read, and trashed pages" do
    books(:manual).press Page.new(body: "Thanks from the manual"), title: "Manual page"
    leaves(:summary_page).trashed!

    get search_path(format: :json, q: "Thanks")

    assert_empty response.parsed_body["results"]
  end

  test "show includes published books for anonymous readers" do
    sign_out
    books(:manual).update!(published: true)
    books(:manual).press Page.new(body: "Thanks from the manual"), title: "Manual page"

    get search_path(format: :json, q: "Thanks")

    assert_response :success
    assert_equal [ "Manual page" ], response.parsed_body["results"].map { it["title"] }
  end

  test "show gives snippets as plain text" do
    pages(:welcome).update! body: "findme Tom & Jerry <b>bold</b>"
    leaves(:welcome_page).reindex

    get search_path(format: :json, q: "findme")

    assert_equal "findme Tom & Jerry bold", response.parsed_body["results"].sole["snippet"]
  end

  test "show marks the matched words in a snippet of their own, with no other markup" do
    pages(:welcome).update! body: "findme Tom & Jerry <b>bold</b>"
    leaves(:welcome_page).reindex

    get search_path(format: :json, q: "findme")

    assert_equal "<mark>findme</mark> Tom &amp; Jerry bold", response.parsed_body["results"].sole["marked_snippet"]
  end

  test "show finds nothing for an empty or operator-only query" do
    [ "", "OR", "^$" ].each do |query|
      get search_path(format: :json, q: query)

      assert_response :success
      assert_empty response.parsed_body["results"]
    end
  end
end
