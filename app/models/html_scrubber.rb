class HtmlScrubber < Rails::Html::PermitScrubber
  # Attributes preserved on a surviving <iframe>. Everything else — srcdoc, on*
  # handlers, name — is dropped so only the vetted embed shape survives. An
  # authored sandbox is kept: the attribute can only ever remove privileges
  # relative to no attribute at all, so honoring it never widens anything.
  # See EmbedAllowlist for the host allowlist.
  IFRAME_ATTRIBUTES = %w[ src width height allowfullscreen loading referrerpolicy sandbox title frameborder allow ].freeze

  # Feature-policy tokens permitted in a surviving iframe `allow` attribute. Any
  # other requested capability (camera, microphone, geolocation, …) is dropped.
  IFRAME_ALLOW_TOKENS = %w[
    accelerometer autoplay clipboard-write encrypted-media fullscreen
    gyroscope picture-in-picture web-share
  ].freeze

  # referrerpolicy values that don't leak the reader's full URL to the embed
  # provider; unsafe-url and the downgrade-tolerant default are dropped.
  IFRAME_REFERRER_POLICIES = %w[
    no-referrer origin origin-when-cross-origin same-origin
    strict-origin strict-origin-when-cross-origin
  ].freeze

  def initialize
    super
    self.tags = Rails::Html::WhiteListSanitizer.allowed_tags + %w[
      audio details summary iframe options table tbody td th thead tr video source mark
    ]
  end

  # Keep an <iframe> only when its src host is on the embed allowlist; other tags
  # fall through to the permitted-tag check.
  def keep_node?(node)
    if iframe?(node)
      EmbedAllowlist.allows?(node["src"])
    else
      super
    end
  end

  # Minimize a surviving <iframe> to the vetted attribute set; other tags keep
  # the default attribute scrubbing.
  def scrub_attributes(node)
    if iframe?(node)
      minimize_iframe(node)
    else
      super
    end
  end

  private
    def iframe?(node)
      node.element? && node.name == "iframe"
    end

    def minimize_iframe(node)
      node.attribute_nodes.each do |attr|
        name = attr.name.downcase
        if IFRAME_ATTRIBUTES.include?(name)
          case name
          when "allow"          then node[attr.name] = filtered_allow(attr.value)
          when "referrerpolicy" then filter_referrerpolicy(node, attr)
          end
        else
          attr.remove
        end
      end
    end

    def filter_referrerpolicy(node, attr)
      attr.remove unless IFRAME_REFERRER_POLICIES.include?(attr.value.to_s.strip.downcase)
    end

    # Keep the whole directive, not just its feature name: `autoplay 'none'`
    # truncated to `autoplay` would grant a capability the author explicitly
    # withheld.
    def filtered_allow(value)
      value.to_s.split(";")
        .map { |directive| directive.strip }
        .select { |directive| IFRAME_ALLOW_TOKENS.include?(directive.split(/\s+/).first.to_s.downcase) }
        .uniq
        .join("; ")
    end
end
