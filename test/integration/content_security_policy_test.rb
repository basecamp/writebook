require "test_helper"

class ContentSecurityPolicyTest < ActionDispatch::IntegrationTest
  test "frame-src carries the approved embed providers" do
    get new_session_url
    assert_response :success

    csp = response.headers["Content-Security-Policy"]
    assert csp.present?, "expected a Content-Security-Policy header"

    frame_src = csp.split(";").map(&:strip).find { |directive| directive.start_with?("frame-src") }
    assert frame_src.present?, "expected a frame-src directive, got: #{csp}"

    tokens = frame_src.split(/\s+/).drop(1) # drop the "frame-src" keyword
    assert_equal EmbedProvider.csp_frame_sources.sort, tokens.sort
  end
end
