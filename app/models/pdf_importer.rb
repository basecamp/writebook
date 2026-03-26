class PdfImporter
  class InvalidPdfError < StandardError; end

  def initialize(book, pdf_io)
    raise InvalidPdfError, "No PDF file provided" if pdf_io.blank?
    @book = book
    @reader = PDF::Reader.new(pdf_io)
  rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError => e
    raise InvalidPdfError, e.message
  end

  def import
    ActiveRecord::Base.transaction do
      pdf_pages.flat_map { |page| leaves_for(page) }
    end
  end

  private
    def pdf_pages
      @reader.pages.each_with_index.filter_map do |page, index|
        parsed = PdfPage.new(page, index + 1)
        parsed unless parsed.blank?
      end
    end

    def leaves_for(pdf_page)
      leaves = []
      leaves << @book.press(Page.new(body: pdf_page.body), title: pdf_page.title) if pdf_page.body.present?
      pdf_page.pictures.each do |attachment|
        picture = Picture.new
        picture.image.attach(attachment)
        leaves << @book.press(picture, title: pdf_page.title)
      end
      leaves
    end
end
