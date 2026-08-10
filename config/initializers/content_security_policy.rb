# Be sure to restart your server when you modify this file.

# Baseline application-wide Content-Security-Policy, deployed in Report-Only
# mode: browsers evaluate the policy and report violations (once a report
# endpoint is wired up) but enforce nothing, so rendering cannot break.
# Tune the policy against observed violations, then flip
# `content_security_policy_report_only` off to enforce it.
#
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

# Session-stable nonce for permitted inline scripts (the importmap JSON + shim,
# auto-nonced by importmap-rails).
#
# The nonce is stable across a session's requests so Turbo snapshot restores
# don't replay a stale nonce and trip CSP. It's the HMAC of a stable cookie
# value keyed by the server secret: the cookie is client-settable, but the
# client can't predict the resulting nonce without knowing secret_key_base.
#
# Writebook sets no per-session verification cookie, so the lightweight
# nonce_id cookie — set on first visit, present for every session including
# unauthenticated ones — is the sole identifier.
module CSP
  module Nonce
    COOKIE = "writebook_csp_nonce_id"

    def self.generate(request)
      hmac(nonce_id(request))
    end

    def self.hmac(identifier)
      OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, identifier)
    end

    # Read or initialize a stable nonce identifier cookie.
    def self.nonce_id(request)
      request.cookies[COOKIE] || set_nonce_id(request)
    end

    def self.set_nonce_id(request)
      value = SecureRandom.base64(16)
      request.cookie_jar[COOKIE] = { value: value, httponly: true, same_site: :lax }
      value
    end
  end

  # Per-install CSP extras.
  #
  # Writebook is a ONCE product: each customer self-hosts it on their own domain
  # and an admin may embed or connect to external hosts — video/embed providers,
  # image CDNs, analytics, form or webhook endpoints — that vary per install and
  # are unknown at build time. `:self` already tracks this install's own origin;
  # these ENV knobs let an admin allow additional hosts without editing this file
  # (and without which enforcement would break their legitimate integrations).
  #
  # Each is a comma-, semicolon-, or whitespace-separated list of CSP source
  # expressions, e.g.
  #
  #   CSP_EXTRA_FRAME_SRC="https://www.youtube.com https://player.vimeo.com"
  #
  # Leave them unset (the default) to keep each directive at :self only.
  EXTRA_ENV = {
    script_src:  "CSP_EXTRA_SCRIPT_SRC",
    style_src:   "CSP_EXTRA_STYLE_SRC",
    img_src:     "CSP_EXTRA_IMG_SRC",
    connect_src: "CSP_EXTRA_CONNECT_SRC",
    frame_src:   "CSP_EXTRA_FRAME_SRC",
    form_action: "CSP_EXTRA_FORM_ACTION"
  }.freeze

  # Parse one ENV knob into a list of extra host sources.
  #
  # Semicolons are tokenized like commas/whitespace: because the nonce forces a
  # per-request policy build, a stray `;` in a value (a plausible operator paste,
  # e.g. "https://youtube.com; https://vimeo.com") would otherwise land inside a
  # single source token and make Rails raise InvalidDirectiveError on every
  # request — a site-wide 500 even in report-only mode. Splitting on `;` yields
  # valid tokens instead; Rails still validates each one, so no injection is
  # introduced (a token with an embedded space still fails validation).
  def self.extra(directive)
    ENV[EXTRA_ENV.fetch(directive)].to_s.split(/[,;\s]+/).reject(&:blank?)
  end

  # Build the baseline policy. Kept as a reusable method so it can be exercised
  # in isolation by tests as well as at boot.
  def self.apply(policy)
    policy.default_src     :self
    policy.script_src      :self, *extra(:script_src)  # nonce auto-appended via nonce_directives below
    # unsafe_inline retained: many style="…" attributes and the per-user
    # hide_from_user_style_tag can't be nonced yet.
    policy.style_src       :self, :unsafe_inline, *extra(:style_src)
    # frame_src / img_src / connect_src start at :self plus any per-install extras
    # and get tuned against violation reports during the report-only window.
    policy.img_src         :self, :data, :blob, *extra(:img_src)
    policy.connect_src     :self, *extra(:connect_src)
    # frame-src is the render-time half of the iframe embed allowlist. It consumes
    # EmbedAllowlist — the same source of truth HtmlScrubber uses at author-time —
    # so a permitted-provider frame the scrubber keeps is one the browser will load,
    # and the two enforcement points cannot drift. (Includes extra(:frame_src).)
    policy.frame_src       :self, *::EmbedAllowlist.frame_src_sources
    policy.frame_ancestors :self
    policy.base_uri        :self
    policy.form_action     :self, *extra(:form_action)
    policy.object_src      :none
    # Specify URI for violation reports once a report sink is available
    # policy.report_uri "/csp-violation-report-endpoint"
  end
end

# Single source of truth for which iframe embed providers Writebook permits.
#
# Consumed at two enforcement points that must never disagree:
#   - display-time, by HtmlScrubber, which strips any <iframe> whose src host is
#     not on this list every time page content renders — stored Markdown stays
#     raw, so the list applies retroactively to existing content; and
#   - browser-side, by the CSP frame-src directive below, which refuses to load
#     a frame from an origin not on this list.
# Both derive their host set from here, so an operator who adds a provider gets
# it honored in both places from one change.
#
# Defined here (not app/models) because the CSP policy is built at boot, before
# app autoloading can resolve an app/models constant; HtmlScrubber references it
# at request time, by which point it is defined.
#
# ── PRODUCT DECISION ──────────────────────────────────────────────────────────
# DEFAULT_PROVIDERS is the shipped default allowlist. Writebook is a ONCE product
# (each customer self-hosts on their own domain), so the *mechanism* is per-
# install configurable via the CSP_EXTRA_FRAME_SRC ENV — the same tokens CSP
# frame-src reads. But the shipped default list below, the per-provider attribute
# policy, and whether a raw-iframe escape hatch exists are product/authoring calls
# an owner must confirm before this enforces. Set DEFAULT_PROVIDERS to {} to ship
# with no built-in providers.
module EmbedAllowlist
  # Provider name => host matcher(s). A leading "*." matches any subdomain but
  # not the apex, mirroring CSP host-source semantics — list the apex separately
  # when both are wanted. Product-owned default list — curate before enforcing.
  DEFAULT_PROVIDERS = {
    "YouTube"     => %w[ www.youtube.com youtube.com www.youtube-nocookie.com ],
    "Vimeo"       => %w[ player.vimeo.com ],
    "Loom"        => %w[ www.loom.com ],
    "Google Maps" => %w[ www.google.com ]
  }.freeze

  ALLOWED_SCHEMES = %w[ https ].freeze

  class << self
    # Every host on the allowlist: the built-in defaults plus any hosts parsed
    # out of the per-install CSP_EXTRA_FRAME_SRC ENV.
    def hosts
      (default_hosts + extra_hosts).uniq
    end

    # True when +src+ is an https URL, on the default port, whose host is on
    # the allowlist. A non-default port must be rejected here because the CSP
    # sources carry no port — and a portless CSP source matches only the
    # scheme's default port, so a kept iframe on :8443 would be one the
    # browser then refuses to load.
    def allows?(src)
      uri = parse(src)
      return false unless uri && ALLOWED_SCHEMES.include?(uri.scheme) && uri.host.present? && uri.port == uri.default_port

      host = uri.host.downcase
      hosts.any? { |pattern| host_matches?(host, pattern) }
    end

    # CSP frame-src source expressions for this same allowlist: the default
    # provider origins as https:// URLs, plus the raw per-install extras (already
    # CSP source expressions). Consumed by the CSP frame-src directive below so
    # frame-src and the scrubber cannot drift.
    def frame_src_sources
      (default_hosts.map { |host| "https://#{host}" } + CSP.extra(:frame_src)).uniq
    end

    private
      def default_hosts
        DEFAULT_PROVIDERS.values.flatten
      end

      def extra_hosts
        CSP.extra(:frame_src).filter_map { |source| host_from_source(source) }
      end

      def parse(src)
        URI.parse(src.to_s.strip)
      rescue URI::InvalidURIError
        nil
      end

      # Mirrors CSP host-source semantics: a "*." pattern covers subdomains
      # only, never the apex, so the scrubber keeps exactly the frames the
      # frame-src directive will load.
      def host_matches?(host, pattern)
        pattern = pattern.downcase
        if pattern.start_with?("*.")
          host.end_with?(pattern.delete_prefix("*"))
        else
          host == pattern
        end
      end

      # Extract a host from a CSP source expression the scrubber can honor
      # faithfully: "https://www.youtube.com" or "https://*.vimeo.com". Anything
      # narrower or stranger than a plain https origin — a path, a port, a
      # scheme-only or keyword token — returns nil: stripping the qualifier
      # would make the scrubber accept more than the CSP source actually
      # allows, so such sources feed frame-src only and admit no iframes.
      def host_from_source(source)
        token = source.to_s.strip
        return nil if token.start_with?("'")

        token = token.delete_prefix("https://").delete_prefix("http://")
        if token.blank? || token.include?("/") || token.include?(":")
          nil
        else
          token
        end
      end
  end
end

Rails.application.configure do
  config.content_security_policy { |policy| CSP.apply(policy) }

  config.content_security_policy_nonce_generator = ->(request) { CSP::Nonce.generate(request) }
  config.content_security_policy_nonce_directives = %w[ script-src ]

  # Report violations without enforcing the policy.
  config.content_security_policy_report_only = true
end
