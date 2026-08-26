require "test_helper"

class EmbedProviderTest < ActiveSupport::TestCase
  teardown { ENV.delete("WRITEBOOK_EMBED_PROVIDERS") }

  # --- default providers: valid embeds pass ---------------------------------

  {
    "YouTube"          => "https://www.youtube.com/embed/dQw4w9WgXcQ",
    "YouTube (nocookie)" => "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ",
    "Vimeo"            => "https://player.vimeo.com/video/76979871",
    "Loom"             => "https://www.loom.com/embed/0123456789abcdef",
    "Google Maps"      => "https://www.google.com/maps/embed?pb=!1m18!1m12!1m3"
  }.each do |name, url|
    test "#{name} embed is allowed" do
      assert EmbedProvider.allows?(url), "expected #{url} to be allowed"
    end
  end

  test "bare and www hosts both allowed" do
    assert EmbedProvider.allows?("https://youtube.com/embed/abc")
    assert EmbedProvider.allows?("https://www.youtube.com/embed/abc")
  end

  # --- disallowed origins ----------------------------------------------------

  test "unknown origin is rejected" do
    assert_not EmbedProvider.allows?("https://evil.com/embed/abc")
  end

  test "valid host with wrong path shape is rejected" do
    assert_not EmbedProvider.allows?("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    assert_not EmbedProvider.allows?("https://player.vimeo.com/channels/staffpicks")
    assert_not EmbedProvider.allows?("https://www.google.com/maps/place/foo")
  end

  # --- allowlist bypass attempts --------------------------------------------

  test "path-prefix boundary tricks are rejected" do
    assert_not EmbedProvider.allows?("https://www.youtube.com/embedxyz/evil")
    assert_not EmbedProvider.allows?("https://www.youtube.com/embedded")
  end

  test "dot-segment and encoded traversal past the prefix are rejected" do
    assert_not EmbedProvider.allows?("https://www.youtube.com/embed/../watch?v=x")
    assert_not EmbedProvider.allows?("https://www.youtube.com/embed/%2e%2e/watch")
    assert_not EmbedProvider.allows?("https://www.youtube.com/embed%2fx")
  end

  test "explicit non-default port is rejected (CSP is host-only, implicit 443)" do
    assert_not EmbedProvider.allows?("https://www.youtube.com:444/embed/x")
    assert EmbedProvider.allows?("https://www.youtube.com:443/embed/x")
  end

  test "protocol-relative url is rejected" do
    assert_not EmbedProvider.allows?("//www.youtube.com/embed/abc")
  end

  test "non-https schemes are rejected" do
    assert_not EmbedProvider.allows?("http://www.youtube.com/embed/abc")
    assert_not EmbedProvider.allows?("data:text/html,<script>alert(1)</script>")
    assert_not EmbedProvider.allows?("javascript:alert(1)")
  end

  test "userinfo host confusion is rejected" do
    assert_not EmbedProvider.allows?("https://www.youtube.com@evil.com/embed/abc")
    assert_not EmbedProvider.allows?("https://evil.com@www.youtube.com/embed/abc")
  end

  test "lookalike hostnames are rejected" do
    assert_not EmbedProvider.allows?("https://notyoutube.com/embed/abc")
    assert_not EmbedProvider.allows?("https://youtube.com.evil.com/embed/abc")
  end

  test "host is matched case-insensitively" do
    assert EmbedProvider.allows?("https://WWW.YOUTUBE.COM/embed/abc")
  end

  test "trailing-dot host is rejected (CSP would not match it)" do
    assert_not EmbedProvider.allows?("https://www.youtube.com./embed/abc")
  end

  test "blank and malformed srcs are rejected" do
    assert_not EmbedProvider.allows?(nil)
    assert_not EmbedProvider.allows?("")
    assert_not EmbedProvider.allows?("https://")
  end

  # --- CSP frame-src derives from the same table ----------------------------

  test "csp_frame_sources reflects exactly the default table" do
    assert_equal %w[
      https://youtube.com https://www.youtube.com
      https://youtube-nocookie.com https://www.youtube-nocookie.com
      https://player.vimeo.com
      https://loom.com https://www.loom.com
      https://google.com https://www.google.com
    ], EmbedProvider.csp_frame_sources
  end

  # --- per-install config extends BOTH scrubber and CSP ---------------------

  test "operator-configured provider extends both the scrubber allowance and CSP" do
    ENV["WRITEBOOK_EMBED_PROVIDERS"] =
      %([{"name":"Wistia","hosts":["fast.wistia.net"],"path_prefix":"/embed/"}])

    # scrubber allowance
    assert EmbedProvider.allows?("https://fast.wistia.net/embed/iframe/abc123")
    assert_not EmbedProvider.allows?("https://fast.wistia.net/other/abc123")

    # CSP directive — same table, so the host is now present too
    assert_includes EmbedProvider.csp_frame_sources, "https://fast.wistia.net"
    # defaults still present
    assert_includes EmbedProvider.csp_frame_sources, "https://www.youtube.com"
  end

  test "default providers carry only the vetted attribute set" do
    provider = EmbedProvider.match("https://www.youtube.com/embed/abc")
    assert_equal EmbedProvider::PERMITTED_ATTRIBUTES, provider.attributes
    %w[srcdoc sandbox name onload style allow referrerpolicy].each do |forbidden|
      assert_not_includes provider.attributes, forbidden
    end
  end

  test "operator config cannot reintroduce forbidden attributes" do
    ENV["WRITEBOOK_EMBED_PROVIDERS"] =
      %([{"name":"X","hosts":["x.example"],"path_prefix":"/e","attributes":["src","srcdoc","sandbox","onload","style","allow","referrerpolicy"]}])

    provider = EmbedProvider.match("https://x.example/e/1")
    assert_equal %w[src], provider.attributes
  end

  test "invalid config json is ignored, defaults survive" do
    ENV["WRITEBOOK_EMBED_PROVIDERS"] = "{not valid json"
    assert EmbedProvider.allows?("https://www.youtube.com/embed/abc")
    assert_not EmbedProvider.allows?("https://x.example/e/1")
  end

  test "a single provider object (not wrapped in an array) is accepted" do
    ENV["WRITEBOOK_EMBED_PROVIDERS"] =
      %({"name":"Wistia","hosts":["fast.wistia.net"],"path_prefix":"/embed/"})
    assert EmbedProvider.allows?("https://fast.wistia.net/embed/iframe/abc")
    assert_includes EmbedProvider.csp_frame_sources, "https://fast.wistia.net"
  end

  test "wildcard, whitespace and over-broad config entries are rejected, defaults survive" do
    [
      %([{"name":"a","hosts":["*"],"path_prefix":"/e"}]),
      %([{"name":"b","hosts":["*.example.com"],"path_prefix":"/e"}]),
      %([{"name":"c","hosts":["x.example bad"],"path_prefix":"/e"}]),
      %([{"name":"d","hosts":["x.example"],"path_prefix":"/"}]),
      %([{"name":"e","hosts":["127.1"],"path_prefix":"/e"}]),
      %([{"name":"f","hosts":["0x7f.1"],"path_prefix":"/e"}])
    ].each do |config|
      ENV.delete("WRITEBOOK_EMBED_PROVIDERS")
      defaults = EmbedProvider.csp_frame_sources
      ENV["WRITEBOOK_EMBED_PROVIDERS"] = config
      # A fully-rejected entry leaves exactly the defaults — no wildcard, no
      # whitespace, no IP-literal, and no path-prefix-of-"/" catch-all leaks in.
      assert_equal defaults, EmbedProvider.csp_frame_sources, config
      assert_not EmbedProvider.allows?("https://x.example/anything"), config
    end
  end
end
