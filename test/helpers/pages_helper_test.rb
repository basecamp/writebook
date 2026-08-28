require "test_helper"

class PagesHelperTest < ActionView::TestCase
  test "sanitize_content keeps an approved-provider iframe" do
    html = %(<iframe src="https://www.youtube.com/embed/dQw4w9WgXcQ"></iframe>)
    result = sanitize_content(html)

    assert_includes result, "<iframe"
    assert_includes result, %(src="https://www.youtube.com/embed/dQw4w9WgXcQ")
  end

  test "sanitize_content strips a disallowed-origin iframe" do
    html = %(<iframe src="https://evil.example/embed/x"></iframe>)
    assert_not_includes sanitize_content(html), "<iframe"
  end

  test "sanitize_content strips a valid host used with the wrong path shape" do
    html = %(<iframe src="https://www.youtube.com/watch?v=dQw4w9WgXcQ"></iframe>)
    assert_not_includes sanitize_content(html), "<iframe"
  end

  test "sanitize_content strips forbidden attributes from an approved iframe" do
    html = %(<iframe src="https://player.vimeo.com/video/76979871" ) +
           %(srcdoc="<script>alert(1)</script>" sandbox="" onload="alert(1)" name="x" ) +
           %(style="position:fixed" allow="camera *" referrerpolicy="unsafe-url" ) +
           %(width="640" allowfullscreen></iframe>)
    result = sanitize_content(html)

    assert_includes result, "<iframe"
    # Match on the attribute name= form so "allow" doesn't false-hit allowfullscreen.
    %w[srcdoc= sandbox= onload= name= style= allow= referrerpolicy=].each do |forbidden|
      assert_not_includes result, forbidden
    end
    assert_includes result, %(width="640")
    assert_includes result, "allowfullscreen"
  end

  test "sanitize_content strips a bare srcdoc iframe with no src" do
    html = %(<iframe srcdoc="<script>alert(1)</script>"></iframe>)
    assert_not_includes sanitize_content(html), "<iframe"
  end
end
