class HtmlScrubber < Rails::Html::PermitScrubber
  def initialize
    super
    self.tags = Rails::Html::WhiteListSanitizer.allowed_tags + %w[
      audio details summary iframe options table tbody td th thead tr video source mark
    ]
  end

  # An <iframe> survives only when an approved provider vouches for its src (host
  # + path shape). Every other tag keeps the default PermitScrubber behavior.
  def keep_node?(node)
    if node.name == "iframe"
      EmbedProvider.allows?(node["src"])
    else
      super
    end
  end

  # For a kept <iframe>, strip every attribute the matching provider doesn't
  # permit — so srcdoc, sandbox, name, on* handlers, style, and allow/referrer
  # policies can't ride along on an otherwise-approved embed. The surviving
  # attributes carry no author-controlled URI or CSS value (src itself is
  # validated by EmbedProvider), so no further per-value sanitizing is needed.
  def scrub_attributes(node)
    if node.name == "iframe"
      permitted = EmbedProvider.match(node["src"])&.attributes || []
      node.attribute_nodes.each do |attr|
        node.remove_attribute(attr.name) unless permitted.include?(attr.name)
      end
    else
      super
    end
  end
end
