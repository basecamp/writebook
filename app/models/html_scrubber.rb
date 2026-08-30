class HtmlScrubber < Rails::Html::PermitScrubber
  # MarkdownRenderer wires generated image anchors to the lightbox with exactly this
  # action. It's the only data-action value allowed to survive, so authored HTML
  # can't bind arbitrary (including auto-firing) Stimulus/Turbo actions to the page's
  # controllers. The value is inert on its own: it opens the lightbox on click,
  # reading the anchor's already-scrubbed href.
  LIGHTBOX_ACTION = "lightbox#open:prevent".freeze

  # Attributes the extra media/embed tags need that aren't in Loofah's safe set.
  # Deliberately excludes value-sensitive iframe attributes (allow, referrerpolicy,
  # sandbox) that can delegate capabilities or leak referrers.
  MEDIA_ATTRIBUTES = %w[
    controls autoplay muted playsinline allowfullscreen frameborder loading open reversed
  ].freeze

  def initialize
    super
    self.tags = Rails::Html::WhiteListSanitizer.allowed_tags + %w[
      audio details summary iframe options table tbody td th thead tr video source mark
    ]
    # Base on Loofah's vetted safe-attribute set rather than an unset list. An unset
    # list falls back to Loofah's default scrub, whose data-* wildcard lets stored
    # content carry a self-firing Stimulus/Turbo gadget (data-controller,
    # data-turbo-*). The explicit set omits that wildcard; on* handlers and srcdoc
    # are dropped, and URL/CSS values are still scrubbed.
    self.attributes = Loofah::HTML5::SafeList::ACCEPTABLE_ATTRIBUTES.to_a \
      + MEDIA_ATTRIBUTES + %w[ data-action ]
  end

  def scrub(node)
    super.tap do
      remove_foreign_actions(node) if node.element?
    end
  end

  # ARIA is a non-scriptable namespace Loofah allows by wildcard; keep it.
  def scrub_attribute?(name)
    return false if name.start_with?("aria-") || name == "role"
    super
  end

  private
    # The renderer emits the lightbox action only on <a>, where Stimulus's default
    # event is click. Restricting to <a> keeps the eventless action from binding to
    # a default-event element that fires without interaction (e.g. <details> toggle).
    def remove_foreign_actions(node)
      node.attribute_nodes.each do |attr|
        next unless attr.name == "data-action"
        attr.remove unless node.name == "a" && attr.value == LIGHTBOX_ACTION
      end
    end
end
