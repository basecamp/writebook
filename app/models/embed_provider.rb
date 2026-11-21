# Which third-party <iframe> embeds are permitted in authored book content.
#
# The allowlist is opt-in. With nothing configured, embeds stay permissive:
# HtmlScrubber keeps an <iframe> from any origin (attributes still scrubbed) and
# no Content-Security-Policy is sent. Once a provider table is configured, both
# enforcement points read from it so they can't drift:
#
#   * author-time  — HtmlScrubber keeps an <iframe> only when its src matches a
#                    provider's host *and* path shape, and strips every attribute
#                    the provider doesn't permit.
#   * render-time  — a `frame-src` directive derived from the same table (see
#                    ApplicationController).
#
# The table comes from, in order of precedence:
#
#   1. WRITEBOOK_EMBED_PROVIDERS — a JSON array of entries; the operator's
#      per-install config, and the way an existing install opts in.
#   2. Account#embed_providers — the same entries, stored per install. FirstRun
#      seeds DEFAULTS here, so a new install starts on the curated list while an
#      install upgraded from before the setting keeps embeds as they were.
#   3. Neither — permissive.
#
# Whichever source applies is the whole table. There is no raw-iframe escape
# hatch once configured: an embed is permitted only if a provider vouches for it.
class EmbedProvider
  # The widest set of attributes any provider may carry through the scrubber.
  # Deliberately excludes srcdoc, sandbox, name and any on* handler (script /
  # frame-busting), style (CSS exfil + overlay clickjacking), and allow /
  # referrerpolicy (delegating powerful features or leaking the full URL to the
  # embed) — so no configured provider can reintroduce them. Embeds are sized
  # with width/height and go fullscreen with allowfullscreen; nothing here
  # carries an author-controlled value that needs further sanitizing (src is
  # validated by host + path below).
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

  # The curated table a new install starts with — the common authoring cases,
  # each pinned to its approved path shape. In config-entry form, so it is also
  # the value an existing install sets to opt in to the same list.
  DEFAULTS = [
    {
      "name" => "YouTube",
      "hosts" => %w[youtube.com www.youtube.com youtube-nocookie.com www.youtube-nocookie.com],
      "path_prefix" => "/embed"
    },
    {
      "name" => "Vimeo",
      "hosts" => %w[player.vimeo.com],
      "path_prefix" => "/video"
    },
    {
      "name" => "Loom",
      "hosts" => %w[loom.com www.loom.com],
      "path_prefix" => "/embed"
    },
    {
      "name" => "Google Maps",
      "hosts" => %w[google.com www.google.com],
      "path_prefix" => "/maps/embed"
    }
  ].freeze

  Resolution = Struct.new(:source, :entries, :providers)

  class << self
    # True once a provider table is configured — by environment or by the
    # account — and the allowlist is enforced. False leaves embeds permissive.
    def configured?
      !resolution.entries.nil?
    end

    def all
      resolution.providers
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

    # CSP `frame-src` sources derived from the same table, or nil when
    # permissive (no directive is sent). Host granularity here (implicit :443,
    # matching the port the scrubber requires); path-shape enforcement lives in
    # the scrubber. Always https. A configured table with no valid entry fails
    # closed.
    def csp_frame_sources
      if configured?
        all.flat_map(&:csp_sources).uniq.presence || [ :none ]
      end
    end

    # Fragment cache keys wrapping scrubbed content include this: a cached
    # fragment skips the scrubber, so it must be invalidated whenever the policy
    # that produced it changes — permissive to configured, or an edit to the
    # table. Digested in resolution order because match is first-match-wins:
    # reordering overlapping entries changes the policy.
    def cache_version
      if configured?
        ActiveSupport::Digest.hexdigest all.map(&:signature).join("\n")
      else
        "permissive"
      end
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
      # Resolved once per distinct configuration: the scrubber, the CSP directive
      # and the fragment cache key all consult the table several times per
      # request, and a parse failure or a rejected entry should be logged once,
      # not per call. A changed environment value or account row is a new
      # source, so it is picked up on the next read without a restart.
      def resolution
        source = [ ENV["WRITEBOOK_EMBED_PROVIDERS"].presence, Account.first&.embed_providers ]
        resolved = @resolution
        resolved = @resolution = resolve(source) unless resolved&.source == source
        resolved
      end

      def resolve(source)
        raw, account_entries = source
        entries = parse_environment(raw) || account_entries
        Resolution.new(source, entries, build(entries)).freeze
      end

      def parse_environment(raw)
        if raw
          parsed = JSON.parse(raw)
          parsed.is_a?(Array) ? parsed : [ parsed ]
        end
      rescue JSON::ParserError
        Rails.logger.warn("[EmbedProvider] WRITEBOOK_EMBED_PROVIDERS is not valid JSON; ignoring")
        nil
      end

      def build(entries)
        Array(entries).filter_map { |entry| normalize_config(entry) }.map { |attributes| new(**attributes) }.freeze
      end

      def normalize_config(entry)
        return unless entry.is_a?(Hash)

        hosts = Array(entry["hosts"] || entry["host"]).map { |host| host.to_s.strip.downcase }
        hosts = hosts.select { |host| host.match?(HOST_FORMAT) }
        path_prefix = canonical_path_prefix(entry["path_prefix"])

        if hosts.empty? || path_prefix.nil?
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

      # Canonical form of a configured prefix: leading slash, duplicate slashes
      # collapsed, no trailing slash. Nil — the entry is dropped — for a dot
      # segment or anything that reduces to the root: a browser resolves "/.",
      # "/./" and "//" to "/", so storing them verbatim would turn the entry
      # into a whole-host allowance.
      def canonical_path_prefix(prefix)
        prefix = prefix.to_s
        segments = prefix.split("/").reject(&:empty?)

        if prefix.start_with?("/") && segments.any? && (segments & %w[. ..]).empty?
          "/#{segments.join("/")}"
        end
      end
  end

  attr_reader :name, :hosts, :path_prefix, :attributes

  def initialize(name:, hosts:, path_prefix:, attributes: nil)
    @name = name
    @hosts = Array(hosts).map { |host| normalize_host(host) }
    @path_prefix = path_prefix
    # Intersect with the master list so no configured provider can widen the
    # attribute surface beyond what the scrubber vets.
    @attributes = (attributes || PERMITTED_ATTRIBUTES) & PERMITTED_ATTRIBUTES
  end

  def allows?(uri)
    hosts.include?(normalize_host(uri.host)) && path_allowed?(uri.path)
  end

  def csp_sources
    hosts.map { |host| "https://#{host}" }
  end

  def signature
    [ hosts, path_prefix, attributes ].to_json
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
