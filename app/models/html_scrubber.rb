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

  # Bump whenever the scrubbing rules tighten. Fragment caches wrapping scrubbed
  # content key on cache_version, so a fragment rendered under the old rules —
  # or under a previous embed policy — is re-scrubbed rather than served verbatim.
  POLICY_VERSION = 1

  def self.cache_version
    "#{POLICY_VERSION}-#{EmbedProvider.cache_version}"
  end

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

  # Once an embed allowlist is configured, an <iframe> survives only when an
  # approved provider vouches for its src (host + path shape). Otherwise, and
  # for every other tag, the default PermitScrubber behavior applies.
  def keep_node?(node)
    if node.name == "iframe" && EmbedProvider.configured?
      EmbedProvider.allows?(node["src"])
    else
      super
    end
  end

  # For a kept <iframe> under the allowlist, strip every attribute the matching
  # provider doesn't permit — so srcdoc, sandbox, name, on* handlers, style, and
  # allow/referrer policies can't ride along on an otherwise-approved embed. The
  # surviving attributes carry no author-controlled URI or CSS value (src itself
  # is validated by EmbedProvider), so no further per-value sanitizing is needed.
  def scrub_attributes(node)
    if node.name == "iframe" && EmbedProvider.configured?
      permitted = EmbedProvider.match(node["src"])&.attributes || []
      node.attribute_nodes.each do |attr|
        node.remove_attribute(attr.name) unless permitted.include?(attr.name)
      end
    else
      super
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
