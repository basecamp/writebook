require "test_helper"

class PagesApiTest < ActionDispatch::IntegrationTest
  test "creating a page from a document" do
    assert_difference -> { books(:handbook).leaves.count }, +1 do
      post_document document(title: "Monitors", body: "How to configure monitors.", external_id: "monitors.md")
    end

    assert_response :created

    leaf = books(:handbook).leaves.find_by!(external_id: "monitors.md")
    assert_equal "Monitors", leaf.title
    assert_equal "How to configure monitors.", leaf.page.body.content.to_s
    assert_in_body 'title: "Monitors"'
  end

  test "creating with a position lands the page there" do
    post_document document(title: "First!", body: "Body", external_id: "first.md", position: 0)

    assert_equal "First!", books(:handbook).leaves.active.positioned.first.title
  end

  test "re-posting the same external_id updates instead of duplicating" do
    post_document document(title: "Monitors", body: "Original", external_id: "monitors.md")
    assert_response :created

    assert_no_difference -> { books(:handbook).leaves.count } do
      post_document document(title: "Monitors", body: "Updated", external_id: "monitors.md")
    end

    assert_response :success
    assert_equal "Updated", books(:handbook).leaves.find_by!(external_id: "monitors.md").page.body.content.to_s
  end

  test "re-posting identical content records no edit" do
    post_document document(title: "Monitors", body: "Same", external_id: "monitors.md")

    travel 1.hour do
      assert_no_difference -> { Edit.count } do
        post_document document(title: "Monitors", body: "Same", external_id: "monitors.md")
      end
    end
  end

  test "re-posting the external_id of a trashed leaf restores it" do
    post_document document(title: "Monitors", body: "Body", external_id: "monitors.md")
    leaf = books(:handbook).leaves.find_by!(external_id: "monitors.md")
    leaf.trashed!

    assert_no_difference -> { books(:handbook).leaves.count } do
      post_document document(title: "Monitors", body: "Body", external_id: "monitors.md")
    end

    assert leaf.reload.active?
  end

  test "updating a page by id" do
    put book_page_path(books(:handbook), leaves(:welcome_page), format: :md),
      params: document(title: "Welcome!", body: "New body"), headers: markdown_headers(:david)

    assert_response :success
    assert_equal "Welcome!", leaves(:welcome_page).reload.title
    assert_equal "New body", leaves(:welcome_page).page.body.content.to_s
  end

  test "putting back what you get is a no-op" do
    get leafable_slug_path(leaves(:welcome_page), format: :md), headers: bearer_key_header(:david)
    exported = response.body

    travel 1.hour do
      assert_no_difference -> { Edit.count } do
        put book_page_path(books(:handbook), leaves(:welcome_page), format: :md),
          params: exported, headers: markdown_headers(:david)
      end
    end

    get leafable_slug_path(leaves(:welcome_page), format: :md), headers: bearer_key_header(:david)
    assert_equal exported, response.body
  end

  test "titles with quotes survive the round trip" do
    post_document document(title: %(A "quoted" title), body: "Body", external_id: "quoted.md")
    leaf = books(:handbook).leaves.find_by!(external_id: "quoted.md")

    get leafable_slug_path(leaf, format: :md), headers: bearer_key_header(:david)
    put book_page_path(books(:handbook), leaf, format: :md), params: response.body, headers: markdown_headers(:david)

    assert_equal %(A "quoted" title), leaf.reload.title
  end

  test "destroy trashes, not destroys" do
    assert_no_difference -> { Leaf.count } do
      delete book_page_path(books(:handbook), leaves(:welcome_page), format: :json),
        headers: bearer_key_header(:david)
    end

    assert_response :no_content
    assert leaves(:welcome_page).reload.trashed?
  end

  test "a malformed document is rejected" do
    post_document "No front matter here"

    assert_response :unprocessable_entity
  end

  test "a reader's key cannot write" do
    post_document document(title: "Nope", body: "Nope"), user: :jz

    assert_response :forbidden
  end

  test "an unrelated user's key cannot even see a private book" do
    books(:handbook).accesses.where(user: users(:kevin)).delete_all

    post_document document(title: "Nope", body: "Nope"), user: :kevin

    assert_response :not_found
  end

  test "bearer key writes skip CSRF protection" do
    ActionController::Base.allow_forgery_protection = true

    post_document document(title: "No token", body: "Body")

    assert_response :created
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  private
    def document(title:, body:, external_id: nil, position: nil)
      front = [ "---", "title: #{JSON.generate(title)}" ]
      front << "external_id: #{JSON.generate(external_id)}" if external_id
      front << "position: #{position}" if position
      (front + [ "---", "", body ]).join("\n")
    end

    def post_document(doc, user: :david)
      post book_pages_path(books(:handbook), format: :md), params: doc, headers: markdown_headers(user)
    end

    def markdown_headers(user)
      bearer_key_header(user).merge("Content-Type" => "text/markdown")
    end
end
