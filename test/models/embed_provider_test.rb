require "test_helper"

class EmbedProviderTest < ActiveSupport::TestCase
  setup { accounts(:signal).update!(embed_providers: EmbedProvider::DEFAULTS) }

  # --- opt-in: permissive until a table is configured -----------------------

  test "permissive when neither the environment nor the account configures a table" do
    accounts(:signal).update!(embed_providers: nil)

    assert_not EmbedProvider.configured?
    assert_empty EmbedProvider.all
    assert_nil EmbedProvider.csp_frame_sources
    assert_equal "permissive", EmbedProvider.cache_version
  end

  test "permissive on an install with no account row at all" do
    Account.delete_all

    assert_not EmbedProvider.configured?
    assert_nil EmbedProvider.csp_frame_sources
  end

  test "the account setting configures the allowlist" do
    assert EmbedProvider.configured?
    assert EmbedProvider.allows?("https://www.youtube.com/embed/abc")
    assert_not EmbedProvider.allows?("https://evil.com/embed/abc")
  end

  test "the environment configures the allowlist on an install with no setting" do
    accounts(:signal).update!(embed_providers: nil)
    ENV["WRITEBOOK_EMBED_PROVIDERS"] = %([{"name":"Wistia","hosts":["fast.wistia.net"],"path_prefix":"/embed/"}])

    assert EmbedProvider.configured?
    assert EmbedProvider.allows?("https://fast.wistia.net/embed/iframe/abc")
    assert_equal %w[https://fast.wistia.net], EmbedProvider.csp_frame_sources
  end

  test "the environment replaces the account setting rather than extending it" do
    ENV["WRITEBOOK_EMBED_PROVIDERS"] = %([{"name":"Wistia","hosts":["fast.wistia.net"],"path_prefix":"/embed/"}])

    assert EmbedProvider.allows?("https://fast.wistia.net/embed/iframe/abc")
    assert_not EmbedProvider.allows?("https://www.youtube.com/embed/abc")
    assert_equal %w[https://fast.wistia.net], EmbedProvider.csp_frame_sources
  end

  test "the curated defaults are config entries, so they round-trip through the environment" do
    accounts(:signal).update!(embed_providers: nil)
    ENV["WRITEBOOK_EMBED_PROVIDERS"] = EmbedProvider::DEFAULTS.to_json

    assert EmbedProvider.allows?("https://www.youtube.com/embed/abc")
    assert_equal EmbedProvider::DEFAULTS.flat_map { |entry| entry["hosts"].map { |host| "https://#{host}" } },
      EmbedProvider.csp_frame_sources
  end

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

  test "csp_frame_sources reflects exactly the configured table" do
    assert_equal %w[
      https://youtube.com https://www.youtube.com
      https://youtube-nocookie.com https://www.youtube-nocookie.com
      https://player.vimeo.com
      https://loom.com https://www.loom.com
      https://google.com https://www.google.com
    ], EmbedProvider.csp_frame_sources
  end

  # --- config validation -----------------------------------------------------

  test "default providers carry only the vetted attribute set" do
    provider = EmbedProvider.match("https://www.youtube.com/embed/abc")
    assert_equal EmbedProvider::PERMITTED_ATTRIBUTES, provider.attributes
    %w[srcdoc sandbox name onload style allow referrerpolicy].each do |forbidden|
      assert_not_includes provider.attributes, forbidden
    end
  end

  test "config cannot reintroduce forbidden attributes" do
    ENV["WRITEBOOK_EMBED_PROVIDERS"] =
      %([{"name":"X","hosts":["x.example"],"path_prefix":"/e","attributes":["src","srcdoc","sandbox","onload","style","allow","referrerpolicy"]}])

    provider = EmbedProvider.match("https://x.example/e/1")
    assert_equal %w[src], provider.attributes
  end

  test "invalid environment json is ignored, the account setting still applies" do
    ENV["WRITEBOOK_EMBED_PROVIDERS"] = "{not valid json"
    assert EmbedProvider.allows?("https://www.youtube.com/embed/abc")
    assert_not EmbedProvider.allows?("https://x.example/e/1")
  end

  test "a rejected entry or unparsable value is logged once per distinct configuration, not per call" do
    ENV["WRITEBOOK_EMBED_PROVIDERS"] = %([{"name":"typo-#{SecureRandom.hex(4)}","hosts":["*"],"path_prefix":"/e"}])
    log = capture_embed_provider_log do
      3.times { EmbedProvider.all }
      3.times { EmbedProvider.csp_frame_sources }
    end
    assert_equal 1, log.scan("ignoring invalid provider entry").size, log

    ENV["WRITEBOOK_EMBED_PROVIDERS"] = "{not valid json #{SecureRandom.hex(4)}"
    log = capture_embed_provider_log do
      3.times { EmbedProvider.configured? }
      3.times { EmbedProvider.all }
    end
    assert_equal 1, log.scan("not valid JSON").size, log
  end

  test "a changed configuration is picked up without a restart" do
    ENV["WRITEBOOK_EMBED_PROVIDERS"] = %([{"hosts":["a.example"],"path_prefix":"/a"}])
    assert EmbedProvider.allows?("https://a.example/a/1")

    ENV["WRITEBOOK_EMBED_PROVIDERS"] = %([{"hosts":["b.example"],"path_prefix":"/b"}])
    assert_not EmbedProvider.allows?("https://a.example/a/1")
    assert EmbedProvider.allows?("https://b.example/b/1")

    ENV.delete("WRITEBOOK_EMBED_PROVIDERS")
    accounts(:signal).update!(embed_providers: [ { "hosts" => [ "c.example" ], "path_prefix" => "/c" } ])
    assert EmbedProvider.allows?("https://c.example/c/1")
    assert_not EmbedProvider.allows?("https://b.example/b/1")
  end

  test "a single provider object (not wrapped in an array) is accepted" do
    ENV["WRITEBOOK_EMBED_PROVIDERS"] =
      %({"name":"Wistia","hosts":["fast.wistia.net"],"path_prefix":"/embed/"})
    assert EmbedProvider.allows?("https://fast.wistia.net/embed/iframe/abc")
    assert_includes EmbedProvider.csp_frame_sources, "https://fast.wistia.net"
  end

  test "root-equivalent path prefixes are rejected and the table fails closed" do
    %w[/ /. /./ // /embed/.. /embed/../ /embed/./.. embed].each do |prefix|
      ENV["WRITEBOOK_EMBED_PROVIDERS"] = %([{"name":"x","hosts":["x.example"],"path_prefix":"#{prefix}"}])

      assert EmbedProvider.configured?, prefix
      assert_equal [ :none ], EmbedProvider.csp_frame_sources, prefix
      assert_not EmbedProvider.allows?("https://x.example/anything"), prefix
      assert_not EmbedProvider.allows?("https://x.example/./anything"), prefix
      assert_not EmbedProvider.allows?("https://x.example//anything"), prefix
    end
  end

  test "a configured path prefix is stored in canonical form" do
    ENV["WRITEBOOK_EMBED_PROVIDERS"] = %([{"name":"x","hosts":["x.example"],"path_prefix":"/embed//x/"}])

    provider = EmbedProvider.match("https://x.example/embed/x/1")
    assert_equal "/embed/x", provider.path_prefix
    assert_not EmbedProvider.allows?("https://x.example/embed/xy")
    assert_not EmbedProvider.allows?("https://x.example/embed/../x/1")
  end

  test "wildcard, whitespace and over-broad config entries are rejected and the table fails closed" do
    [
      %([{"name":"a","hosts":["*"],"path_prefix":"/e"}]),
      %([{"name":"b","hosts":["*.example.com"],"path_prefix":"/e"}]),
      %([{"name":"c","hosts":["x.example bad"],"path_prefix":"/e"}]),
      %([{"name":"d","hosts":["x.example"],"path_prefix":"/"}]),
      %([{"name":"e","hosts":["127.1"],"path_prefix":"/e"}]),
      %([{"name":"f","hosts":["0x7f.1"],"path_prefix":"/e"}])
    ].each do |config|
      ENV["WRITEBOOK_EMBED_PROVIDERS"] = config
      # A fully-rejected entry leaves a configured but empty table — no wildcard,
      # no whitespace, no IP-literal, and no path-prefix-of-"/" catch-all leaks
      # in, and nothing falls back to a wider source.
      assert_equal [ :none ], EmbedProvider.csp_frame_sources, config
      assert_not EmbedProvider.allows?("https://x.example/anything"), config
    end
  end

  # --- fragment cache version tracks the effective policy -------------------

  test "cache_version distinguishes permissive from configured and follows the table" do
    configured = EmbedProvider.cache_version
    assert_equal configured, EmbedProvider.cache_version

    accounts(:signal).update!(embed_providers: nil)
    assert_equal "permissive", EmbedProvider.cache_version

    ENV["WRITEBOOK_EMBED_PROVIDERS"] = %([{"name":"x","hosts":["x.example"],"path_prefix":"/e"}])
    with_host = EmbedProvider.cache_version
    assert_not_equal configured, with_host

    ENV["WRITEBOOK_EMBED_PROVIDERS"] = %([{"name":"x","hosts":["x.example"],"path_prefix":"/e","attributes":["src"]}])
    assert_not_equal with_host, EmbedProvider.cache_version

    ENV["WRITEBOOK_EMBED_PROVIDERS"] = %([{"name":"x","hosts":["x.example"],"path_prefix":"/f"}])
    assert_not_equal with_host, EmbedProvider.cache_version
  end

  test "cache_version follows resolution order, since match is first-match-wins" do
    ENV["WRITEBOOK_EMBED_PROVIDERS"] =
      %([{"hosts":["x.example"],"path_prefix":"/e","attributes":["src"]},{"hosts":["x.example"],"path_prefix":"/e"}])
    narrow_first = EmbedProvider.cache_version
    assert_equal %w[src], EmbedProvider.match("https://x.example/e/1").attributes

    ENV["WRITEBOOK_EMBED_PROVIDERS"] =
      %([{"hosts":["x.example"],"path_prefix":"/e"},{"hosts":["x.example"],"path_prefix":"/e","attributes":["src"]}])
    assert_not_equal narrow_first, EmbedProvider.cache_version
    assert_equal EmbedProvider::PERMITTED_ATTRIBUTES, EmbedProvider.match("https://x.example/e/1").attributes
  end

  private
    def capture_embed_provider_log
      log = StringIO.new
      capture = ActiveSupport::Logger.new(log)
      Rails.logger.broadcast_to(capture)
      yield
      log.string
    ensure
      Rails.logger.stop_broadcasting_to(capture)
    end
end
