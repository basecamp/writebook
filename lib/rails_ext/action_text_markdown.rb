module ActionText
  class Markdown < Record
    # The signed id that authorizes an upload is rendered into the page editor. Binding
    # it to a purpose keeps it from being used anywhere else a signed global id is
    # accepted, and expiring it bounds how long a copy taken off the page stays good.
    # Neither replaces the authorization check in the uploads controller.
    UPLOADS_SIGNED_ID_PURPOSE = :markdown_uploads
    UPLOADS_SIGNED_ID_EXPIRY = 1.day

    DEFAULT_RENDERER_OPTIONS = {
      filter_html: false
    }

    DEFAULT_MARKDOWN_EXTENSIONS = {
      autolink: true,
      highlight: true,
      no_intra_emphasis: true,
      fenced_code_blocks: true,
      lax_spacing: true,
      strikethrough: true,
      tables: true
    }

    mattr_accessor :renderer, default: Redcarpet::Markdown.new(
      Redcarpet::Render::HTML.new(DEFAULT_RENDERER_OPTIONS), DEFAULT_MARKDOWN_EXTENSIONS)

    belongs_to :record, polymorphic: true, touch: true

    def to_html
      (renderer.try(:call) || renderer).render(content).html_safe
    end
  end
end

module ActionText::Markdown::Uploads
  extend ActiveSupport::Concern

  included do
    has_many_attached :uploads, dependent: :destroy
  end
end

# to_prepare, not on_load(:active_storage_attachment): the load hook only fired
# once something else happened to load ActiveStorage::Attachment, leaving uploads
# undefined in a process serving an upload as its first storage-touching request.
# has_many_attached isn't defined until after the initializers, so it can't run here.
Rails.application.config.to_prepare do
  ActionText::Markdown.include ActionText::Markdown::Uploads
end

ActiveSupport.run_load_hooks :action_text_markdown, ActionText::Markdown
