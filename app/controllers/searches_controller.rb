# Search across every book the reader can see, for API clients: GET with a
# `q` parameter, answered in JSON. The in-book search box stays on
# Books::SearchesController.
class SearchesController < ApplicationController
  allow_unauthenticated_access
  allow_api_token_access only: :show

  def show
    @leaves = Leaf.active.where(book: Book.accessable_or_published).search(params[:q]).favoring_title.includes(:book).limit(50)

    respond_to do |format|
      format.json
    end
  end
end
