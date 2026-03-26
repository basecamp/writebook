class PdfPage
  MIN_TITLE_LENGTH = 3
  MAX_TITLE_LENGTH = 100

  attr_reader :pictures

  def initialize(page, page_number)
    @page = page
    @page_number = page_number
    @text = page.text.strip
    @pictures = PdfPicture.extract_from(page)
  end

  def blank?
    @text.blank? && @pictures.empty?
  end

  def title
    first_line = @text.lines.first&.strip
    if first_line.present? && first_line.length.between?(MIN_TITLE_LENGTH, MAX_TITLE_LENGTH)
      first_line
    else
      "Page #{@page_number}"
    end
  end

  def body
    @text.gsub(/\n{3,}/, "\n\n").strip
  end
end
