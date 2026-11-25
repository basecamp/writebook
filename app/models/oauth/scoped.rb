# What a device grant and the tokens minted from it may do: "read write" for
# full access, or "read" for a read-only token, which reads the books its user
# can read and nothing more. Tokens inherit their scope and never widen it.
module Oauth::Scoped
  extend ActiveSupport::Concern

  READ = "read"
  FULL = "read write"

  included do
    validates :scope, inclusion: { in: [ READ, FULL ] }
  end

  class_methods do
    # RFC 6749 §3.3: a space-delimited list. Asking for nothing means full access.
    def normalize_scope(requested)
      values = requested.to_s.split

      if (values - %w[ read write ]).any?
        raise Oauth::Error.invalid_scope
      elsif values.include?("write") || values.empty?
        FULL
      else
        READ
      end
    end
  end

  def read_only?
    scope == READ
  end
end
