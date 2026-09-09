class ApplicationController < ActionController::Base
  include Authentication, Authorization, VersionHeaders

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Render-time half of the iframe embed allowlist: once a provider table is
  # configured, `frame-src` is derived from the same table HtmlScrubber reads so
  # the two can't drift. Left unset while permissive, so nothing that renders
  # today is blocked, and only `frame-src` is set — the rest of the policy is
  # deliberately unrestricted.
  content_security_policy if: -> { EmbedProvider.configured? } do |policy|
    policy.frame_src(*EmbedProvider.csp_frame_sources)
  end
end
