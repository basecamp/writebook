require "test_helper"

class SectionsApiTest < ActionDispatch::IntegrationTest
  test "creating a section with JSON" do
    assert_difference -> { books(:handbook).leaves.count }, +1 do
      post book_sections_path(books(:handbook), format: :json),
        params: { leaf: { title: "The Basics" }, external_id: "the-basics", position: 0 },
        headers: bearer_key_header(:david), as: :json
    end

    assert_response :created

    leaf = books(:handbook).leaves.find_by!(external_id: "the-basics")
    assert_equal "Section", leaf.leafable_type
    assert_equal "The Basics", leaf.title
    assert_equal "The Basics", leaf.section.body
    assert_equal leaf, books(:handbook).leaves.active.positioned.first
    assert_equal leaf.id, response.parsed_body["id"]
  end

  test "re-posting the same external_id updates instead of duplicating" do
    2.times do |round|
      assert_difference -> { books(:handbook).leaves.count }, round.zero? ? +1 : 0 do
        post book_sections_path(books(:handbook), format: :json),
          params: { leaf: { title: "The Basics" }, section: { theme: "vol#{round}" }, external_id: "the-basics" },
          headers: bearer_key_header(:david), as: :json
      end
    end

    assert_equal "vol1", books(:handbook).leaves.find_by!(external_id: "the-basics").section.theme
  end

  test "re-posting identical content records no edit" do
    params = { leaf: { title: "The Basics" }, section: { body: "The Basics" }, external_id: "the-basics" }

    post book_sections_path(books(:handbook), format: :json),
      params: params, headers: bearer_key_header(:david), as: :json

    travel 1.hour do
      assert_no_difference -> { Edit.count } do
        post book_sections_path(books(:handbook), format: :json),
          params: params, headers: bearer_key_header(:david), as: :json
      end
    end
  end

  test "updating a section by id" do
    put book_section_path(books(:handbook), leaves(:welcome_section), format: :json),
      params: { leaf: { title: "Renamed" }, section: { body: "Renamed" } },
      headers: bearer_key_header(:david), as: :json

    assert_response :success
    assert_equal "Renamed", leaves(:welcome_section).reload.title
    assert_equal "Renamed", leaves(:welcome_section).section.body
  end

  test "a reader's key cannot write sections" do
    post book_sections_path(books(:handbook), format: :json),
      params: { leaf: { title: "Nope" } }, headers: bearer_key_header(:jz), as: :json

    assert_response :forbidden
  end
end
