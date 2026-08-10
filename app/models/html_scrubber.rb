class HtmlScrubber < Rails::Html::PermitScrubber
  # Attributes preserved on a surviving <iframe>. Everything else — srcdoc, on*
  # handlers, name, sandbox overrides, arbitrary allow — is dropped so only the
  # vetted embed shape survives. See EmbedAllowlist for the host allowlist.
  IFRAME_ATTRIBUTES = %w[ src width height allowfullscreen loading referrerpolicy title frameborder allow ].freeze

  # Feature-policy tokens permitted in a surviving iframe `allow` attribute. Any
  # other requested capability (camera, microphone, geolocation, …) is dropped.
  IFRAME_ALLOW_TOKENS = %w[
    accelerometer autoplay clipboard-write encrypted-media fullscreen
    gyroscope picture-in-picture web-share
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
          node[attr.name] = filtered_allow(attr.value) if name == "allow"
        else
          attr.remove
        end
      end
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
