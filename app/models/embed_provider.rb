# Single source of truth for which third-party <iframe> embeds are permitted in
# authored book content. Both enforcement points read from here so they can't
# drift:
#
#   * author-time  — HtmlScrubber keeps an <iframe> only when its src matches a
#                    provider's host *and* path shape, and strips every attribute
#                    the provider doesn't permit.
#   * render-time  — the Content-Security-Policy `frame-src` directive is derived
#                    from the same table (see config/initializers/
#                    content_security_policy.rb).
#
# Writebook is self-hosted, so operators extend the table per install via the
# WRITEBOOK_EMBED_PROVIDERS environment variable (JSON). Extending it widens the
# scrubber allowance and the CSP directive together — there is no separate list
# to keep in sync, and there is no raw-iframe escape hatch: an embed is permitted
# only if a provider in this table vouches for it.
class EmbedProvider
  # The widest set of attributes any provider may carry through the scrubber.
  # Deliberately excludes srcdoc, sandbox, name and any on* handler (script /
  # frame-busting), style (CSS exfil + overlay clickjacking), and allow /
  # referrerpolicy (delegating powerful features or leaking the full URL to the
  # embed) — so neither a default nor an operator-supplied provider can
  # reintroduce them. Embeds are sized with width/height and go fullscreen with
  # allowfullscreen; nothing here carries an author-controlled value that needs
  # further sanitizing (src is validated by host + path below).
  PERMITTED_ATTRIBUTES = %w[
    src width height allowfullscreen frameborder title loading
  ].freeze

  # A DNS hostname: one or more [a-z0-9-] labels joined by dots, ending in an
  # alphabetic-initial TLD label — no wildcard, no whitespace, and no IP literal.
  # Requiring an alphabetic final label rejects IPv4 spellings (127.1,
  # 2130706433, 0x7f.1, 0177.0.0.1) that Ruby parses but browsers canonicalize
  # differently than the CSP source this table emits — which would otherwise let
  # the scrubber keep a frame the CSP blocks. Guards operator config so a bad
  # host can't widen (or, with embedded whitespace, crash) the derived directive.
  HOST_FORMAT = /\A(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z](?:[a-z0-9-]*[a-z0-9])?\z/

  # Shipped defaults — the common authoring cases, each pinned to its approved
  # path shape. host(s) are matched exactly (case-insensitively); path is matched
  # on a segment boundary against path_prefix.
  DEFAULTS = [
    {
      name: "YouTube",
      hosts: %w[youtube.com www.youtube.com youtube-nocookie.com www.youtube-nocookie.com],
      path_prefix: "/embed"
    },
    {
      name: "Vimeo",
      hosts: %w[player.vimeo.com],
      path_prefix: "/video"
    },
    {
      name: "Loom",
      hosts: %w[loom.com www.loom.com],
      path_prefix: "/embed"
    },
    {
      name: "Google Maps",
      hosts: %w[google.com www.google.com],
      path_prefix: "/maps/embed"
    }
  ].freeze

  class << self
    def all
      (DEFAULTS + configured).map { |attributes| new(**attributes) }
    end

    # The provider vouching for +src+, or nil. Used by the scrubber both to decide
    # whether to keep the <iframe> and to learn which attributes it may retain.
    def match(src)
      return if src.blank?

      uri = parse(src)
      return unless uri

      all.find { |provider| provider.allows?(uri) }
    end

    def allows?(src)
      !match(src).nil?
    end

    # CSP `frame-src` sources derived from the same table. Host granularity here
    # (implicit :443, matching the port the scrubber requires); path-shape
    # enforcement lives in the scrubber. Always https.
    def csp_frame_sources
      all.flat_map(&:csp_sources).uniq
    end

    # Parses +src+ into a URI only when it is a fetchable https URL, on the
    # default port, with a host and no embedded userinfo (which would let
    # "https://youtube.com@evil.com/…" read as trusted). Anything else —
    # protocol-relative, data:, javascript:, http:, an explicit non-443 port,
    # malformed — yields nil and is therefore never matched.
    def parse(src)
      uri = URI.parse(src.to_s.strip)
      return unless uri.is_a?(URI::HTTPS)
      return if uri.host.blank? || uri.userinfo.present?
      return if uri.port != uri.default_port

      uri
    rescue URI::InvalidURIError
      nil
    end

    private
      def configured
        raw = ENV["WRITEBOOK_EMBED_PROVIDERS"]
        return [] if raw.blank?

        parsed = JSON.parse(raw)
        entries = parsed.is_a?(Array) ? parsed : [ parsed ]
        entries.filter_map { |entry| normalize_config(entry) }
      rescue JSON::ParserError
        Rails.logger.warn("[EmbedProvider] WRITEBOOK_EMBED_PROVIDERS is not valid JSON; ignoring")
        []
      end

      def normalize_config(entry)
        return unless entry.is_a?(Hash)

        hosts = Array(entry["hosts"] || entry["host"]).map { |host| host.to_s.strip.downcase }
        hosts = hosts.select { |host| host.match?(HOST_FORMAT) }
        path_prefix = entry["path_prefix"].to_s

        if hosts.empty? || !valid_path_prefix?(path_prefix)
          Rails.logger.warn("[EmbedProvider] ignoring invalid provider entry: #{entry.inspect}")
          return
        end

        attributes = entry["attributes"]
        {
          name: entry["name"].to_s.presence || hosts.first,
          hosts: hosts,
          path_prefix: path_prefix,
          attributes: attributes.nil? ? nil : Array(attributes).map(&:to_s)
        }
      end

      def valid_path_prefix?(prefix)
        prefix.start_with?("/") && prefix.length > 1
      end
  end

  attr_reader :name, :hosts, :path_prefix, :attributes

  def initialize(name:, hosts:, path_prefix:, attributes: nil)
    @name = name
    @hosts = Array(hosts).map { |host| normalize_host(host) }
    @path_prefix = path_prefix.chomp("/")
    # Intersect with the master list so no provider — default or operator-supplied
    # — can widen the attribute surface beyond what the scrubber vets.
    @attributes = (attributes || PERMITTED_ATTRIBUTES) & PERMITTED_ATTRIBUTES
  end

  def allows?(uri)
    hosts.include?(normalize_host(uri.host)) && path_allowed?(uri.path)
  end

  def csp_sources
    hosts.map { |host| "https://#{host}" }
  end

  private
    # Case-insensitive only. A trailing dot is *not* stripped: "youtube.com." is a
    # distinct hostname to a CSP `frame-src` source, so tolerating it here would let
    # the scrubber keep a frame the CSP blocks. Left unmatched, it is rejected.
    def normalize_host(host)
      host.to_s.downcase
    end

    # Segment-boundary prefix match: "/embed" permits "/embed" and "/embed/<id>"
    # but not "/embedded" or "/watch". Dot-segments and percent-encoded dot/slash
    # are rejected outright so a path the browser would canonicalize past the
    # prefix (e.g. "/embed/../watch") can't slip through.
    def path_allowed?(path)
      return false if path.blank? || traversal?(path)

      path == path_prefix || path.start_with?("#{path_prefix}/")
    end

    def traversal?(path)
      path.split("/").include?("..") || path.match?(/%2e|%2f/i)
    end
end
