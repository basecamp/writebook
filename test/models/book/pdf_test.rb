require "test_helper"

class Book::PdfTest < ActiveSupport::TestCase
  setup do
    @book = books(:handbook)
    @leaves = @book.leaves.active.with_leafables.positioned
  end

  test "renders a valid pdf across every leaf type" do
    leaves(:welcome_page).leafable.update!(body: "# Heading\n\nSome **bold** text and a list:\n\n- one\n- two")

    pdf = Book::Pdf.new(@book, @leaves).render

    assert pdf.start_with?("%PDF"), "expected PDF header"
    assert_includes pdf, "%%EOF"
    assert_operator pdf.bytesize, :>, 1000
  end

  test "respects the requested page size" do
    letter = Book::Pdf.new(@book, @leaves, page_size: "LETTER").render
    a4 = Book::Pdf.new(@book, @leaves, page_size: "A4").render

    assert_match %r{/MediaBox \[0 0 612}, letter   # US Letter: 612 x 792 pt
    assert_match %r{/MediaBox \[0 0 595}, a4        # A4: 595.28 x 841.89 pt
  end

  test "does not raise on non-Latin (Greek) content" do
    leaves(:welcome_page).leafable.update!(body: "# Καλωσήρθες\n\nπερίληψη")

    assert_nothing_raised do
      Book::Pdf.new(@book, @leaves).render
    end
  end

  test "renders every markdown construct without raising" do
    leaves(:welcome_page).leafable.update!(body: <<~MD)
      Paragraph with **bold**, _italic_, ~~struck~~, `code`, and a [link](https://example.com/?a=1&b=2).

      1. first
      2. second
         - nested a
         - nested b

      > A quote.

      ```
      code block
      ```

      ---

      | Name | R&D |
      | ---- | --- |
      | a    | b   |
    MD

    pdf = Book::Pdf.new(@book, @leaves).render

    assert pdf.start_with?("%PDF")
    assert_includes pdf, "%%EOF"
  end
end
