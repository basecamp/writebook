require "test_helper"

class HtmlScrubberTest < ActiveSupport::TestCase
  test "keeps an allowlisted-provider iframe" do
    html = %(<p>hi</p><iframe src="https://www.youtube.com/embed/abc"></iframe>)
    out  = scrub(html)

    assert_includes out, "<iframe"
    assert_includes out, %(src="https://www.youtube.com/embed/abc")
  end

  test "strips an off-allowlist iframe entirely" do
    html = %(<p>before</p><iframe src="https://evil.example/x"></iframe><p>after</p>)
    out  = scrub(html)

    assert_not_includes out, "<iframe"
    assert_not_includes out, "evil.example"
    assert_includes out, "before"
    assert_includes out, "after"
  end

  test "strips an iframe with no src" do
    assert_not_includes scrub(%(<iframe srcdoc="<b>x</b>"></iframe>)), "<iframe"
  end

  test "minimizes attributes on a surviving iframe" do
    html = <<~HTML
      <iframe src="https://player.vimeo.com/video/1"
              width="640" height="360" allowfullscreen
              srcdoc="<script>alert(1)</script>"
              onload="steal()" name="x" sandbox=""></iframe>
    HTML
    out = scrub(html)

    assert_includes out, %(src="https://player.vimeo.com/video/1")
    assert_includes out, "width", "vetted attributes survive"
    assert_not_includes out, "srcdoc", "srcdoc is dropped"
    assert_not_includes out, "onload", "on* handlers are dropped"
    assert_includes out, %(sandbox=""), "an authored sandbox only restricts and survives"
    assert_not_includes out, %(name="x"), "arbitrary attributes are dropped"
  end

  test "filters the iframe allow attribute to a safe token set" do
    html = %(<iframe src="https://www.youtube.com/embed/x" allow="fullscreen; camera; microphone; autoplay"></iframe>)
    out  = scrub(html)

    assert_match %r{allow="[^"]*fullscreen}, out
    assert_match %r{allow="[^"]*autoplay}, out
    assert_not_includes out, "camera"
    assert_not_includes out, "microphone"
  end

  test "keeps an authored sandbox and drops a leaking referrerpolicy" do
    html = %(<iframe src="https://www.youtube.com/embed/x" sandbox="" referrerpolicy="unsafe-url"></iframe>)
    out  = scrub(html)

    assert_includes out, "sandbox", "an authored sandbox only ever restricts; stripping it would grant privileges"
    assert_not_includes out, "referrerpolicy", "unsafe-url leaks the reader's full URL to the provider"
  end

  test "keeps a non-leaking referrerpolicy" do
    out = scrub(%(<iframe src="https://www.youtube.com/embed/x" referrerpolicy="no-referrer"></iframe>))

    assert_includes out, %(referrerpolicy="no-referrer")
  end

  test "keeps an authored allowlist on a surviving allow directive" do
    html = %(<iframe src="https://www.youtube.com/embed/x" allow="autoplay 'none'; clipboard-write https://other.example; camera *"></iframe>)
    out  = scrub(html)

    # Truncating `autoplay 'none'` to `autoplay` would grant what the author withheld.
    assert_includes out, "autoplay 'none'"
    assert_includes out, "clipboard-write https://other.example"
    assert_not_includes out, "camera"
  end

  test "honors a per-install ENV provider" do
    with_env "CSP_EXTRA_FRAME_SRC" => "https://maps.example.test" do
      out = scrub(%(<iframe src="https://maps.example.test/embed"></iframe>))
      assert_includes out, "maps.example.test"
    end
  end

  private
    def scrub(html)
      Loofah.fragment(html).scrub!(HtmlScrubber.new).to_html
    end

    def with_env(vars)
      original = {}
      vars.each_key { |k| original[k] = ENV.key?(k) ? ENV[k] : :__unset__ }
      vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
      yield
    ensure
      original.each { |k, v| v == :__unset__ ? ENV.delete(k) : ENV[k] = v }
    end
end
