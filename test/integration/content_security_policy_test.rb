require "test_helper"

class ContentSecurityPolicyTest < ActionDispatch::IntegrationTest
  test "no policy is sent while embeds are permissive" do
    get new_session_path
    assert_response :success

    assert_nil response.headers["Content-Security-Policy"]
  end

  test "frame-src carries the account's configured providers" do
    accounts(:signal).update!(embed_providers: EmbedProvider::DEFAULTS)

    assert_equal EmbedProvider.csp_frame_sources.sort, frame_src_tokens.sort
  end

  test "an environment-configured table reaches the header without a restart, replacing the account's" do
    accounts(:signal).update!(embed_providers: EmbedProvider::DEFAULTS)
    ENV["WRITEBOOK_EMBED_PROVIDERS"] =
      %([{"name":"Wistia","hosts":["fast.wistia.net"],"path_prefix":"/embed/"}])

    assert_equal %w[https://fast.wistia.net], frame_src_tokens
  end

  test "a configured table with no valid entry fails closed" do
    ENV["WRITEBOOK_EMBED_PROVIDERS"] = %([{"hosts":["*"],"path_prefix":"/e"}])

    assert_equal %w['none'], frame_src_tokens
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
