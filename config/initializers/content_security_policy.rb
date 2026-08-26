# Be sure to restart your server when you modify this file.
#
# Render-time half of the iframe embed allowlist. The `frame-src` directive is
# derived from the EmbedProvider table — the same source of truth the author-time
# HtmlScrubber reads — so the two enforcement points can't drift. Operators
# extend the allowlist per install via WRITEBOOK_EMBED_PROVIDERS (see
# app/models/embed_provider.rb); that widens both the scrubber and this directive
# at once.
#
# The source is a lambda so it's resolved per request (in controller context),
# which keeps the header in lockstep with the provider table without referencing
# an autoloaded constant at boot. Only `frame-src` is set: the rest of the policy
# is intentionally left unrestricted so this hardening is limited to which origins
# may be framed.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.frame_src -> { EmbedProvider.csp_frame_sources.presence || [ :none ] }
  end
end
