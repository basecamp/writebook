class Account < ApplicationRecord
  include Joinable

  # The iframe embed allowlist for this install, as EmbedProvider config entries.
  # Nil leaves embeds permissive; FirstRun seeds the curated defaults for new
  # installs, and an install upgraded from before the column keeps nil.
  serialize :embed_providers, coder: JSON
end
