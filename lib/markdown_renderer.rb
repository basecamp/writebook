require "rouge/plugins/redcarpet"

class MarkdownRenderer < Redcarpet::Render::HTML
  include Rouge::Plugins::Redcarpet

  def self.build
    renderer = MarkdownRenderer.new(ActionText::Markdown::DEFAULT_RENDERER_OPTIONS)
    Redcarpet::Markdown.new(renderer, ActionText::Markdown::DEFAULT_MARKDOWN_EXTENSIONS)
  end

  def initialize(*args)
    super
    @id_counts = Hash.new(0)
  end

  def header(text, header_level)
    unique_id(text).then do |id|
      "<h#{header_level} id='#{id}'>#{text} <a href='##{id}' class='heading__link' aria-hidden='true'>#</a></h#{header_level}>"
    end
  end

  def image(url, title, alt_text)
    url, title, alt_text = [ url, title, alt_text ].map { ERB::Util.html_escape_once(it) }
    %(<a title="#{title}" data-action="lightbox#open:prevent" data-lightbox-target="image" data-lightbox-url-value="#{url}?disposition=attachment" href="#{url}"><img src="#{url}" alt="#{alt_text}"></a>)
  end

  private
    def unique_id(text)
      text.parameterize.then do |base_id|
        @id_counts[base_id] += 1
        @id_counts[base_id] > 1 ? "#{base_id}-#{@id_counts[base_id]}" : base_id
      end
    end
end
