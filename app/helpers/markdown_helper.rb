module MarkdownHelper
  OPTIONS = {
    filter_html: true,
    hard_wrap: true,
    space_after_headers: true
  }

  EXTENSIONS = {
    autolink: true,
    superscript: true,
    disable_indented_code_blocks: true,
    tables: true
  }

  RENDER = Redcarpet::Render::HTML.new(OPTIONS)
  RENDERER = Redcarpet::Markdown.new(RENDER, EXTENSIONS)

  def markdown(text)
    RENDERER.render(text).html_safe
  end
  alias_method :md, :markdown
end
