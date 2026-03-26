require "test_helper"

class Books::ImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :kevin
  end

  test "create imports leaves from a valid PDF" do
    assert_difference -> { books(:handbook).leaves.active.count }, +2 do
      post book_import_path(books(:handbook)), params: {
        pdf: fixture_file_upload("sample.pdf", "application/pdf")
      }
    end

    assert_redirected_to book_slug_url(books(:handbook))
    assert_nil flash[:notice]
  end

  test "create with no file redirects with alert" do
    assert_no_difference -> { Leaf.count } do
      post book_import_path(books(:handbook))
    end

    assert_redirected_to book_slug_url(books(:handbook))
    assert_equal "Could not import PDF.", flash[:alert]
  end

  test "create with a non-PDF file redirects with alert" do
    assert_no_difference -> { Leaf.count } do
      post book_import_path(books(:handbook)), params: {
        pdf: fixture_file_upload("reading.webp", "image/webp")
      }
    end

    assert_redirected_to book_slug_url(books(:handbook))
    assert_equal "Could not import PDF.", flash[:alert]
  end

  test "create logs error when PDF parsing fails" do
    log_output = StringIO.new
    previous_logger = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(log_output)

    assert_no_difference -> { Leaf.count } do
      post book_import_path(books(:handbook)), params: {
        pdf: fixture_file_upload("reading.webp", "image/webp")
      }
    end

    assert_match "PdfImporter failed", log_output.string
    assert_redirected_to book_slug_url(books(:handbook))
    assert_equal "Could not import PDF.", flash[:alert]
  ensure
    Rails.logger = previous_logger
  end

  test "create is forbidden for non-editors" do
    sign_in :jz
    post book_import_path(books(:handbook)), params: {
      pdf: fixture_file_upload("sample.pdf", "application/pdf")
    }
    assert_response :forbidden
  end
end
