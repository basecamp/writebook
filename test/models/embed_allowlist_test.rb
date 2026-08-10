require "test_helper"

class EmbedAllowlistTest < ActiveSupport::TestCase
  test "default providers are allowed with no ENV set" do
    with_env "CSP_EXTRA_FRAME_SRC" => nil do
      assert EmbedAllowlist.allows?("https://www.youtube.com/embed/abc123")
      assert EmbedAllowlist.allows?("https://player.vimeo.com/video/123")
      assert EmbedAllowlist.allows?("https://www.loom.com/embed/xyz")
    end
  end

  test "off-allowlist hosts are rejected" do
    with_env "CSP_EXTRA_FRAME_SRC" => nil do
      assert_not EmbedAllowlist.allows?("https://evil.example/embed")
      assert_not EmbedAllowlist.allows?("https://notyoutube.com/embed")
    end
  end

  test "non-https and non-absolute srcs are rejected" do
    with_env "CSP_EXTRA_FRAME_SRC" => nil do
      assert_not EmbedAllowlist.allows?("http://www.youtube.com/embed/x"), "http is rejected"
      assert_not EmbedAllowlist.allows?("//www.youtube.com/embed/x"),      "protocol-relative is rejected"
      assert_not EmbedAllowlist.allows?("/local/page"),                     "relative is rejected"
      assert_not EmbedAllowlist.allows?("javascript:alert(1)"),            "javascript: is rejected"
      assert_not EmbedAllowlist.allows?(nil)
      assert_not EmbedAllowlist.allows?("")
    end
  end

  test "non-default ports are rejected to match the portless CSP sources" do
    with_env "CSP_EXTRA_FRAME_SRC" => nil do
      assert_not EmbedAllowlist.allows?("https://www.youtube.com:8443/embed/x")
      assert EmbedAllowlist.allows?("https://www.youtube.com:443/embed/x"), "an explicit default port matches like an omitted one"
    end
  end

  test "a per-install ENV host is honored, from the same source CSP frame-src reads" do
    with_env "CSP_EXTRA_FRAME_SRC" => "https://maps.example.test https://forms.example.test" do
      assert EmbedAllowlist.allows?("https://maps.example.test/embed")
      assert EmbedAllowlist.allows?("https://forms.example.test/f/1")
      # and the same host appears in the CSP frame-src source list — no drift.
      assert_includes EmbedAllowlist.frame_src_sources, "https://maps.example.test"
    end
  end

  test "wildcard ENV hosts match the apex and any subdomain" do
    with_env "CSP_EXTRA_FRAME_SRC" => "https://*.example.test" do
      assert EmbedAllowlist.allows?("https://sub.example.test/x")
      assert EmbedAllowlist.allows?("https://deep.sub.example.test/x")
      # CSP host-source semantics: *.example.test covers subdomains, not the apex.
      assert_not EmbedAllowlist.allows?("https://example.test/x")
      assert_not EmbedAllowlist.allows?("https://example.test.evil.com/x")
    end
  end

  test "sources narrower than a plain origin feed CSP only, never the scrubber" do
    with_env "CSP_EXTRA_FRAME_SRC" => "https://example.test/approved/ https://ported.example.test:8443" do
      # Dropping the path or port would let the scrubber accept more than the
      # CSP source allows, so these admit no iframes at all.
      assert_not EmbedAllowlist.allows?("https://example.test/approved/x")
      assert_not EmbedAllowlist.allows?("https://example.test/unapproved")
      assert_not EmbedAllowlist.allows?("https://ported.example.test/x")
      # They still pass through to frame-src verbatim.
      assert_includes EmbedAllowlist.frame_src_sources, "https://example.test/approved/"
    end
  end

  test "frame_src_sources always includes the default provider origins" do
    with_env "CSP_EXTRA_FRAME_SRC" => nil do
      assert_includes EmbedAllowlist.frame_src_sources, "https://www.youtube.com"
      assert_includes EmbedAllowlist.frame_src_sources, "https://player.vimeo.com"
    end
  end

  private
    def with_env(vars)
      original = {}
      vars.each_key { |k| original[k] = ENV.key?(k) ? ENV[k] : :__unset__ }
      vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
      yield
    ensure
      original.each { |k, v| v == :__unset__ ? ENV.delete(k) : ENV[k] = v }
    end
end
