class Books::SearchesController < ApplicationController
  allow_unauthenticated_access
  allow_read_only_token_access only: :show

  include BookScoped

  def show
    @leaves = @book.leaves.active.search(params[:q]).favoring_title.limit(50)

    respond_to do |format|
      format.json { render "searches/show" }
    end
  end

  def create
    @leaves = @book.leaves.active.search(params[:search]).favoring_title.limit(50)
  end
end
