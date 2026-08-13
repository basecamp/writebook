class Books::LeavesController < ApplicationController
  include BookScoped

  allow_bearer_key_access only: :index

  def index
    @leaves = @book.leaves.active.with_leafables.positioned
  end
end
