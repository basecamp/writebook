require "test_helper"

class Leaf::DocumentTest < ActiveSupport::TestCase
  test "generates front matter and body from a leaf" do
    document = Leaf::Document.from(leaves(:welcome_page), url: "http://example.com/1/handbook/2/welcome")

    assert_equal <<~MD.chomp, document.to_s
      ---
      title: "Welcome to The Handbook!"
      url: "http://example.com/1/handbook/2/welcome"
      ---

      This is _such_ a great handbook.
    MD
  end

  test "parses back what it generates, byte for byte" do
    document = Leaf::Document.from(leaves(:welcome_page))
    parsed = Leaf::Document.parse(document.to_s)

    assert_equal document.title, parsed.title
    assert_equal document.body, parsed.body
    assert_equal document.to_s, parsed.to_s
  end

  test "titles with quotes survive the round trip" do
    document = Leaf::Document.new(title: %(A "quoted" title), body: "Body")
    parsed = Leaf::Document.parse(document.to_s)

    assert_equal %(A "quoted" title), parsed.title
  end

  test "bodies containing front matter delimiters survive" do
    body = "Before\n\n---\n\nAfter the rule\n---\nmore"
    document = Leaf::Document.new(title: "Rules", body: body)

    assert_equal body, Leaf::Document.parse(document.to_s).body
  end

  test "bodies keep their exact leading and trailing whitespace" do
    body = "\nStarts blank, ends with two newlines\n\n"
    document = Leaf::Document.new(title: "Space", body: body)
    parsed = Leaf::Document.parse(document.to_s)

    assert_equal body, parsed.body
    assert_equal document.to_s, parsed.to_s
  end

  test "parses hand-authored YAML front matter" do
    parsed = Leaf::Document.parse(<<~MD)
      ---
      title: Monitors
      position: 27
      external_id: monitors.md
      ---

      How to configure monitors.
    MD

    assert_equal "Monitors", parsed.title
    assert_equal 27, parsed.position
    assert_equal "monitors.md", parsed.external_id
    assert_equal "How to configure monitors.\n", parsed.body
  end

  test "ignores url and unknown front matter keys" do
    parsed = Leaf::Document.parse("---\ntitle: T\nurl: http://example.com/x\nwhatever: else\n---\n\nBody")

    assert_equal "T", parsed.title
    assert_nil parsed.url
    assert_equal "Body", parsed.body
  end

  test "binary-encoded requests with UTF-8 content parse" do
    raw = "---\ntitle: Führung\n---\n\nEm — dash".b
    parsed = Leaf::Document.parse(raw)

    assert_equal "Führung", parsed.title
    assert_equal "Em — dash", parsed.body
    assert_equal Encoding::UTF_8, parsed.body.encoding
  end

  test "rejects invalid UTF-8" do
    assert_raises Leaf::Document::Malformed do
      Leaf::Document.parse("---\ntitle: T\n---\n\n\xE2 broken".b)
    end
  end

  test "rejects documents without front matter" do
    assert_raises Leaf::Document::Malformed do
      Leaf::Document.parse("Just a body")
    end

    assert_raises Leaf::Document::Malformed do
      Leaf::Document.parse("---\ntitle: unclosed\n\nBody")
    end

    assert_raises Leaf::Document::Malformed do
      Leaf::Document.parse("---\n- just\n- a\n- list\n---\n\nBody")
    end
  end
end
