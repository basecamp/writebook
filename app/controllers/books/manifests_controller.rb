# The sync manifest: everything a CLI needs to decide what changed remotely —
# book metadata plus every active leaf with its position and fingerprint —
# without downloading any content.
class Books::ManifestsController < ApplicationController
  allow_api_token_access only: :show

  include BookScoped

  def show
    @leaves = @book.leaves.active.with_leafables.positioned
  end
end
