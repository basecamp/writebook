require "test_helper"

class HtmlScrubberTest < ActiveSupport::TestCase
  def scrub(html)
    ApplicationController.helpers.sanitize(html, scrubber: HtmlScrubber.new)
  end

  def render_and_scrub(markdown)
    scrub(ActionText::Markdown.renderer.call.render(markdown))
  end

  test "strips inline event handlers on allowed tags" do
    %w[iframe img video audio details].each do |tag|
      result = scrub(%(<#{tag} onload="alert(1)" onerror="alert(1)"></#{tag}>))
      assert_not_includes result, "onload"
      assert_not_includes result, "onerror"
      assert_not_includes result, "alert(1)"
    end
  end

  test "strips iframe srcdoc so framed markup cannot run script" do
    result = scrub(%(<iframe srcdoc="<script>alert(1)</script>"></iframe>))
    assert_not_includes result, "srcdoc"
    assert_not_includes result, "alert(1)"
  end

  test "strips data-controller and data-turbo gadget attributes" do
    result = scrub(%(<div data-controller="edit-mode" data-turbo-method="delete" data-turbo-stream="x" data-foo="y">hi</div>))
    assert_not_includes result, "data-controller"
    assert_not_includes result, "data-turbo"
    assert_not_includes result, "data-foo"
    assert_includes result, "hi"
  end

  test "strips javascript: URL schemes from href and src" do
    assert_not_includes scrub(%(<a href="javascript:alert(1)">x</a>)), "javascript"
    assert_not_includes scrub(%(<iframe src="javascript:alert(1)"></iframe>)), "javascript"
  end

  test "scrubs javascript from style attributes to block CSS injection" do
    result = scrub(%(<p style="background:url(javascript:alert(1))">x</p>))
    assert_not_includes result, "javascript"
    assert_not_includes result, "alert(1)"
  end

  test "preserves the Markdown renderer's lightbox image wiring" do
    result = render_and_scrub("![cat](/uploads/cat.png)")
    assert_includes result, %(data-action="lightbox#open:prevent")
    assert_includes result, %(href="/uploads/cat.png")
    assert_includes result, %(<img src="/uploads/cat.png" alt="cat">)
  end

  test "allows the lightbox action only on anchors, not arbitrary data-action" do
    # The lightbox action survives only on <a> (where Stimulus's default event is
    # click); it is inert there — opens the image dialog on click, reading the
    # scrubbed href.
    kept = scrub(%(<a data-action="lightbox#open:prevent" href="/x">ok</a>))
    assert_includes kept, %(data-action="lightbox#open:prevent")

    # Foreign actions are stripped outright — including on an <a>, so it's the exact
    # value, not merely the anchor tag, that gates survival.
    %w[
      turbo:load@window->lightbox#open
      load->arrangement#dragStartCreate
      mouseover->scroll-to-highlight#scroll
    ].each do |action|
      %w[div a].each do |tag|
        result = scrub(%(<#{tag} data-action="#{action}" href="/x">x</#{tag}>))
        assert_not_includes result, "data-action", "expected #{action.inspect} on <#{tag}> to be stripped"
      end
    end

    # Even the benign action is stripped off a default-event element that would
    # fire without interaction (<details> toggle fires on the initial `open`).
    details = scrub(%(<details open data-action="lightbox#open:prevent"><summary>s</summary></details>))
    assert_not_includes details, "data-action"
    div = scrub(%(<div data-action="lightbox#open:prevent">x</div>))
    assert_not_includes div, "data-action"
  end

  test "strips value-sensitive iframe attributes but keeps safe embed attributes" do
    result = scrub(%(<iframe src="https://ex.com" allow="camera" referrerpolicy="unsafe-url" sandbox="allow-scripts" allowfullscreen frameborder="0"></iframe>))
    assert_not_includes result, "allow="
    assert_not_includes result, "referrerpolicy"
    assert_not_includes result, "sandbox"
    assert_includes result, "allowfullscreen"
    assert_includes result, %(frameborder="0")
  end

  test "preserves the Markdown renderer's header anchor accessibility markup" do
    result = render_and_scrub("# Introduction")
    assert_includes result, %(id="introduction")
    assert_includes result, %(aria-hidden="true")
  end

  test "preserves ARIA, role, and safe authored link attributes" do
    result = scrub(%(<a href="/x" target="_blank" rel="noopener" dir="rtl" tabindex="0" aria-label="open" role="button">y</a>))
    assert_includes result, %(target="_blank")
    assert_includes result, %(rel="noopener")
    assert_includes result, %(dir="rtl")
    assert_includes result, %(tabindex="0")
    assert_includes result, %(aria-label="open")
    assert_includes result, %(role="button")
  end

  test "preserves legitimate formatting, media, and table markup" do
    assert_includes scrub("<p>Hello <strong>world</strong> <em>now</em></p>"), "<strong>world</strong>"
    assert_includes scrub(%(<a href="https://example.com" title="t">link</a>)), %(href="https://example.com")
    video = scrub(%(<video src="/uploads/v.mp4" controls></video>))
    assert_includes video, "<video"
    assert_includes video, "controls"
    table = scrub("<table><thead><tr><th>H</th></tr></thead><tbody><tr><td>D</td></tr></tbody></table>")
    assert_includes table, "<th>H</th>"
    assert_includes table, "<td>D</td>"
  end
end
