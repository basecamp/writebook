require "prawn"

# Renders a Book as a PDF: full-bleed cover, table of contents, then one
# section/page/picture per leaf, with page numbers in the footer. Pure Ruby
# (Prawn + Nokogiri), so it adds no system dependencies. Reached via the `.pdf`
# format on books#show, mirroring the `.md` export.
#
# Page bodies are markdown; we render that source to HTML with the same renderer
# the app uses elsewhere (Page.preview_renderer) and walk it with Nokogiri,
# emitting Prawn text. Images and tables are pulled out and drawn by Prawn
# directly, since flowing text can't place or size them.
class Book::Pdf
  FONT_DIR = Rails.root.join("app/assets/fonts/inter")

  DEFAULT_PAGE_SIZE = "LETTER"
  MARGIN = 56
  TOC_PER_PAGE = 30   # conservative, so the TOC never overflows its reserved pages
  LINE = 18
  HEADING_SIZES = { "h1" => 18, "h2" => 16, "h3" => 14, "h4" => 13, "h5" => 12, "h6" => 11 }.freeze
  LIST_INDENT = 16
  QUOTE_INDENT = 16

  def initialize(book, leaves, page_size: DEFAULT_PAGE_SIZE)
    @book = book
    @leaves = leaves.to_a
    @page_size = page_size
    @entries = []
  end

  def render
    @pdf = Prawn::Document.new(
      page_size: @page_size, margin: MARGIN,
      info: { Title: @book.title, Author: @book.author.presence })
    use_inter_font

    cover_page
    reserve_toc_pages
    content_pages
    fill_toc
    number_content_pages

    @pdf.render
  end

  private
    # Inter (bundled under app/assets/fonts/inter) covers Latin, Greek, Cyrillic,
    # etc.; Prawn's built-in AFM fonts only cover Windows-1252.
    def use_inter_font
      @pdf.font_families.update("Inter" => {
        normal: FONT_DIR.join("Inter-Regular.ttf").to_s,
        bold: FONT_DIR.join("Inter-Bold.ttf").to_s,
        italic: FONT_DIR.join("Inter-Italic.ttf").to_s,
        bold_italic: FONT_DIR.join("Inter-BoldItalic.ttf").to_s })
      @pdf.font "Inter"
    end

    def cover_page
      @book.cover.attached? ? image_cover(blob_bytes(@book.cover)) : text_cover
    end

    # Fill the whole page edge-to-edge (cover, cropping overflow), no margins.
    def image_cover(bytes)
      width, height = image_dimensions(bytes)
      return text_cover unless width

      @pdf.canvas do
        page_w, page_h = @pdf.bounds.width, @pdf.bounds.height
        scale = [ page_w / width.to_f, page_h / height.to_f ].max
        w, h = width * scale, height * scale
        @pdf.image StringIO.new(bytes), width: w, height: h,
          at: [ (page_w - w) / 2, page_h - (page_h - h) / 2 ]
      end
    rescue Prawn::Errors::UnsupportedImageType
      text_cover
    end

    def text_cover
      @pdf.move_down 220
      @pdf.text @book.title, size: 32, style: :bold, align: :center
      @pdf.move_down 14
      @pdf.text @book.subtitle, size: 18, align: :center if @book.subtitle.present?
      @pdf.move_down 28
      @pdf.text @book.author, size: 14, align: :center if @book.author.present?
    end

    # Reserve blank pages now; each leaf's page number isn't known until the
    # content is laid out, so we go back and fill these in afterwards.
    def reserve_toc_pages
      @toc_start = @pdf.page_number + 1
      @toc_count = [ (@leaves.size / TOC_PER_PAGE.to_f).ceil, 1 ].max
      @toc_count.times { @pdf.start_new_page }
      @first_content_page = @pdf.page_number + 1
    end

    def fill_toc
      page = @toc_start
      @pdf.go_to_page(page)
      @pdf.move_cursor_to @pdf.bounds.top
      @pdf.text @book.title, size: 22, style: :bold   # header mirrors the web sidebar
      @pdf.move_down LINE

      @entries.each do |entry|
        if @pdf.cursor < LINE && page < @toc_start + @toc_count - 1
          page += 1
          @pdf.go_to_page(page)
          @pdf.move_cursor_to @pdf.bounds.top
        end
        toc_entry(entry)
      end
    end

    NUMBER_WIDTH = 28

    # Flat list of leaf titles, mirroring the web sidebar TOC.
    def toc_entry(entry)
      number = (entry[:page] - @first_content_page + 1).to_s
      style = entry[:section] ? :bold : :normal   # section leaves are bold, like the web
      title = entry[:title].to_s
      top = @pdf.cursor
      right = @pdf.bounds.width

      @pdf.text_box link(entry[:anchor], escape(title)), at: [ 0, top ], inline_format: true,
        width: right - NUMBER_WIDTH, height: LINE, overflow: :truncate, style: style
      @pdf.text_box link(entry[:anchor], number), at: [ right - NUMBER_WIDTH, top ], inline_format: true,
        width: NUMBER_WIDTH, height: LINE, align: :right
      dotted_leader(@pdf.width_of(title, style: style) + 4, right - NUMBER_WIDTH - 4, top - 12)
      @pdf.move_down LINE
    end

    def dotted_leader(from, to, y)
      return unless to > from
      @pdf.dash(1, space: 2)
      @pdf.stroke_color "aaaaaa"
      @pdf.stroke_horizontal_line from, to, at: y
      @pdf.stroke_color "000000"
      @pdf.undash
    end

    def link(anchor, content)
      %(<link anchor="#{anchor}">#{content}</link>)
    end

    def content_pages
      @leaves.each_with_index do |leaf, index|
        @pdf.start_new_page
        anchor = "leaf-#{index}"
        @entries << { title: leaf.title, page: @pdf.page_number, anchor: anchor, section: leaf.section? }
        @pdf.add_dest anchor, @pdf.dest_fit
        render_leaf(leaf)
      end
    end

    def render_leaf(leaf)
      if leaf.section?
        @pdf.move_down 160
        @pdf.text leaf.section.body.to_s, size: 26, style: :bold, align: :center
      elsif leaf.picture?
        chapter_title leaf.title
        place_image blob_bytes(leaf.picture.image) if leaf.picture.image.attached?
        @pdf.move_down 8
        @pdf.text leaf.picture.caption, style: :italic, align: :center, size: 11 if leaf.picture.caption.present?
      else
        render_page(leaf)
      end
    end

    def render_page(leaf)
      html = Page.preview_renderer.render(leaf.page.markable)
      chapter_title leaf.title
      # Pull images and tables out and draw them directly; flowing text can't
      # place or size them. Splitting the raw HTML means an image mid-paragraph
      # breaks its paragraph, but markdown keeps images on their own line.
      strip_leading_title(html, leaf.title).split(%r{(<img\b[^>]*>|<table[\s\S]*?</table>)}i).each do |part|
        next if part.blank?
        case part
        when /\A<img\b/i   then place_inline_image(part)
        when /\A<table\b/i then place_table(part)
        else append_html(part)
        end
      end
    end

    # Plain-text rows, no gridlines; swap to prawn-table if real gridlines are
    # ever needed. Cells are HTML-unescaped so "R&D" doesn't print as "R&amp;D".
    def place_table(html)
      rows = html.scan(%r{<tr[^>]*>(.*?)</tr>}mi).map do |(row)|
        row.scan(%r{<t[hd][^>]*>(.*?)</t[hd]>}mi).map { |(cell)| CGI.unescapeHTML(cell.gsub(/<[^>]+>/, " ")).squish }
      end
      return if rows.empty?
      @pdf.move_down 4
      rows.each { |cells| @pdf.text cells.join("   |   "), size: 10 }
      @pdf.move_down 4
    end

    def chapter_title(title)
      return if title.blank?
      @pdf.text title, size: 20, style: :bold
      @pdf.move_down 12
    end

    # Walk the Redcarpet-rendered HTML with Nokogiri and emit Prawn text. Only
    # the tags markdown produces are handled; unknown tags fall through to their
    # inline content.
    def append_html(html)
      Nokogiri::HTML.fragment(html).children.each do |node|
        render_block(node)
      rescue StandardError => e
        # Skip a node we can't render rather than dropping the rest of the page.
        Rails.logger.warn("Book::Pdf skipped <#{node.name}>: #{e.message}")
      end
    end

    def render_block(node)
      case node.name
      when "h1", "h2", "h3", "h4", "h5", "h6"
        @pdf.move_down 6
        @pdf.text inline(node), inline_format: true, size: HEADING_SIZES[node.name], style: :bold
        @pdf.move_down 4
      when "ul", "ol"
        render_list(node, ordered: node.name == "ol")
      when "blockquote"
        @pdf.indent(QUOTE_INDENT) { node.children.each { |child| render_block(child) } }
      when "pre"
        @pdf.move_down 4
        @pdf.text node.text.strip, size: 10
        @pdf.move_down 4
      when "hr"
        @pdf.move_down 6
        @pdf.stroke_horizontal_rule
        @pdf.move_down 6
      when "text"
        @pdf.text escape(node.text), inline_format: true unless node.text.strip.empty?
      else   # p, and anything else carrying inline content
        body = inline(node)
        return if body.strip.empty?
        @pdf.text body, inline_format: true
        @pdf.move_down 6
      end
    end

    def render_list(node, ordered:)
      index = 0
      node.element_children.each do |item|
        next unless item.name == "li"
        index += 1
        marker = ordered ? "#{index}." : "•"
        @pdf.indent(LIST_INDENT) do
          inline_parts = item.children.reject { |c| c.element? && %w[ ul ol ].include?(c.name) }
          text = inline_parts.map { |c| inline_node(c) }.join.strip
          @pdf.text "#{marker}  #{text}", inline_format: true unless text.empty?
          item.children.each { |c| render_block(c) if c.element? && %w[ ul ol ].include?(c.name) }
        end
      end
      @pdf.move_down 4
    end

    # Convert a node's children into a Prawn inline-format string.
    def inline(node)
      node.children.map { |child| inline_node(child) }.join
    end

    def inline_node(node)
      case node.name
      when "text"               then escape(node.text)
      when "strong", "b"        then "<b>#{inline(node)}</b>"
      when "em", "i"            then "<i>#{inline(node)}</i>"
      when "del", "s", "strike" then "<strikethrough>#{inline(node)}</strikethrough>"
      when "code"               then escape(node.text)   # no monospace face bundled
      when "br"                 then "\n"
      when "a"                  then %(<link href="#{escape(node["href"])}">#{inline(node)}</link>)
      else inline(node)
      end
    end

    def place_inline_image(img_tag)
      src = img_tag[/src=["']([^"']+)["']/i, 1]
      bytes = upload_bytes(src)
      place_image(bytes) if bytes
    end

    # Resolve a `/u/<slug>` markdown upload to its blob. External URLs (no
    # matching attachment) are skipped — we can't fetch them.
    def upload_bytes(src)
      slug = src[%r{/u/(.+)\z}, 1]
      slug && blob_bytes(ActiveStorage::Attachment.find_by(slug: slug))
    end

    # Download an attachment's bytes, returning nil if it's missing or the blob
    # file is gone (a missing image shouldn't 500 the whole export).
    def blob_bytes(attachment)
      attachment&.download
    rescue StandardError
      nil
    end

    def place_image(bytes)
      return unless bytes
      @pdf.start_new_page if @pdf.cursor < 220
      @pdf.move_down 6
      @pdf.image StringIO.new(bytes), fit: [ @pdf.bounds.width, @pdf.cursor - 12 ], position: :center
      @pdf.move_down 6
    rescue Prawn::Errors::UnsupportedImageType
      # Prawn embeds only PNG/JPG; skip other formats (webp/gif).
    end

    def image_dimensions(bytes)
      image = Prawn.image_handler.find(bytes).new(bytes)
      [ image.width, image.height ]
    rescue StandardError
      [ nil, nil ]
    end

    # Drop a leading heading that just repeats the leaf title (pages
    # conventionally open with `# Title`), so we don't print it twice.
    def strip_leading_title(html, title)
      html.sub(/\A\s*<h([1-6])>(.*?)<\/h\1>\s*/m) do
        $2.gsub(/<[^>]+>/, "").strip.casecmp?(title.to_s.strip) ? "" : $&
      end
    end

    def number_content_pages
      first = @first_content_page
      @pdf.number_pages "<page>",
        start_count_at: 1, page_filter: ->(i) { i >= first },
        at: [ 0, 0 ], width: @pdf.bounds.width, align: :center, size: 10
    end

    # Escape for Prawn inline formatting. Only &, <, > are markup to Prawn, so
    # (unlike CGI/ERB escapers) we must not touch quotes — Prawn would render
    # `&quot;` literally.
    def escape(string)
      string.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
    end
end
