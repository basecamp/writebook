require "test_helper"

class ContentSecurityPolicyTest < ActionDispatch::IntegrationTest
  PAGE_PATH = "/session/new"

  test "no frame-src is sent while embeds are permissive" do
    get new_session_path
    assert_response :success

    assert_no_match "frame-src", response.headers["Content-Security-Policy"]
  end

  test "enforcing script policy allows exactly the inline scripts the page carries" do
    get new_session_path
    assert_response :success

    policy = response.headers["Content-Security-Policy"]
    assert policy, "expected an enforcing Content-Security-Policy header"
    assert_nil response.headers["Content-Security-Policy-Report-Only"]
    assert_match "object-src 'none'", policy
    assert_match "base-uri 'self'", policy
    assert_no_match "unsafe-inline", policy
    assert_no_match "nonce-", policy
    assert_empty response.headers["Set-Cookie"].to_s.scan(/nonce/i)

    script_src = policy[/script-src ([^;]+)/, 1].split
    inline = Nokogiri::HTML5(response.body).css("script").reject { |s| s["src"] }
    assert_operator inline.size, :>=, 2
    inline.each do |script|
      assert_includes script_src, "'sha256-#{Digest::SHA256.base64digest(script.text)}'", "inline #{script["type"]} script not allowed by hash"
    end
  end

  test "scripts may load from a configured asset host, however it's written" do
    {
      "https://cdn.example.test" => %r{\Ahttps://cdn\.example\.test\z},
      "cdn.example.test" => %r{\Ahttp://cdn\.example\.test\z},
      "//cdn.example.test" => %r{\Ahttp://cdn\.example\.test\z},
      "https://assets%d.example.test" => %r{\Ahttps://assets[0-3]\.example\.test\z},
      ->(source) { "https://one.example.test" } => %r{\Ahttps://one\.example\.test\z},
      ->(source, request) { "https://#{request.host}.example.test" } => %r{\Ahttps://www\.example\.com\.example\.test\z}
    }.each do |asset_host, expected_origin|
      with_asset_host(asset_host) do
        get PAGE_PATH
        follow_redirect! while response.redirect?
        assert_response :success

        script_src = response.headers["Content-Security-Policy"][/script-src ([^;]+)/, 1].split
        page = Nokogiri::HTML5(response.body)
        urls = JSON.parse(page.at_css("script[type=importmap]").text)["imports"].values +
          page.css("link[rel=modulepreload]").map { it["href"] } + page.css("script[src]").map { it["src"] }
        origins = urls.map { URI.join(request.base_url, it).origin }.uniq - [ request.base_url ]

        assert_not_empty origins, asset_host.inspect
        origins.each do |origin|
          assert_match expected_origin, origin, asset_host.inspect
          assert_includes script_src, origin, asset_host.inspect
        end
        assert_includes script_src, "'sha256-#{Digest::SHA256.base64digest(page.at_css("script[type=importmap]").text)}'", asset_host.inspect
      end
    end
  end

  test "with the policy turned off, pages send only frame-src" do
    accounts(:signal).update!(embed_providers: EmbedProvider::DEFAULTS)

    without_policy do
      assert_equal EmbedProvider.csp_frame_sources.sort, frame_src_tokens.sort
      assert_no_match "script-src", response.headers["Content-Security-Policy"]
    end
  end

  test "with the policy turned off and no embeds, pages send none" do
    without_policy do
      get PAGE_PATH
      assert_response :success
      assert_nil response.headers["Content-Security-Policy"]
    end
  end

  test "the escape hatch boots without a policy" do
    output = IO.popen({ "DISABLE_CONTENT_SECURITY_POLICY" => "true" },
      [ "bin/rails", "runner", "print Rails.application.config.content_security_policy.inspect" ], chdir: Rails.root, err: File::NULL, &:read)

    assert_equal "nil", output
  end

  test "uploaded files are guarded on their way out" do
    assert_includes Rails.application.middleware.map(&:klass), UploadedScriptGuard
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
    # What DISABLE_CONTENT_SECURITY_POLICY=true leaves at boot: no application policy
    def without_policy
      previous = Rails.application.env_config.delete("action_dispatch.content_security_policy")
      yield
    ensure
      Rails.application.env_config["action_dispatch.content_security_policy"] = previous
    end

    def with_asset_host(asset_host)
      previous, ApplicationController.asset_host = ApplicationController.asset_host, asset_host
      Rails.application.importmap.send(:clear_cache)
      yield
    ensure
      ApplicationController.asset_host = previous
      Rails.application.importmap.send(:clear_cache)
    end

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
