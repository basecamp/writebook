class Leaf::Document
  class Malformed < StandardError; end

  FRONT_MATTER_DELIMITER = "\n---\n"

  attr_reader :title, :position, :external_id, :body, :url

  # The .md wire format: YAML front matter, then the body, verbatim. The parser
  # takes the first closing delimiter and exactly one blank line after it, so
  # bodies containing --- lines round-trip untouched.
  def self.parse(text)
    raise Malformed, "missing front matter" unless text.start_with?("---\n")

    front, delimiter, body = text[4..].partition(FRONT_MATTER_DELIMITER)
    raise Malformed, "missing closing front matter delimiter" if delimiter.empty?

    attributes = YAML.safe_load(front)
    raise Malformed, "front matter is not a mapping" unless attributes.is_a?(Hash)

    new title: attributes["title"]&.to_s, position: attributes["position"]&.to_i,
      external_id: attributes["external_id"]&.to_s, body: body.delete_prefix("\n")
  rescue Psych::Exception => error
    raise Malformed, error.message
  end

  def self.from(leaf, url: nil)
    new title: leaf.title, external_id: leaf.external_id, body: leaf.leafable.markable.to_s, url: url
  end

  def initialize(title:, body:, position: nil, external_id: nil, url: nil)
    @title, @body, @position, @external_id, @url = title, body, position, external_id, url
  end

  def to_s
    lines = [ "---" ]
    lines << "title: #{JSON.generate(title)}"
    lines << "url: #{JSON.generate(url)}" if url
    lines << "---"

    "#{lines.join("\n")}\n\n#{body}"
  end
end
