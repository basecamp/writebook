require "test_helper"

class ContentSecurityPolicyTest < ActionDispatch::IntegrationTest
  test "frame-src carries the approved embed providers" do
    assert_equal EmbedProvider.csp_frame_sources.sort, frame_src_tokens.sort
  end

  test "an operator-configured provider reaches the header without a restart" do
    ENV["WRITEBOOK_EMBED_PROVIDERS"] =
      %([{"name":"Wistia","hosts":["fast.wistia.net"],"path_prefix":"/embed/"}])

    assert_includes frame_src_tokens, "https://fast.wistia.net"
    assert_includes frame_src_tokens, "https://www.youtube.com"
  end

  private
    def frame_src_tokens
      get new_session_path
      assert_response :success

      csp = response.headers["Content-Security-Policy"]
      assert csp.present?, "expected a Content-Security-Policy header"

      frame_src = csp.split(";").map(&:strip).find { |directive| directive.start_with?("frame-src") }
      assert frame_src.present?, "expected a frame-src directive, got: #{csp}"

      frame_src.split(/\s+/).drop(1)
    end
end
