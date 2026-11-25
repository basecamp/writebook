class Books::PublicationsController < ApplicationController
  include BookScoped

  before_action :ensure_editable, only: %i[ edit update ]

  def show
  end

  def edit
  end

  def update
    @book.update! book_params

    respond_to do |format|
      format.html { redirect_to book_slug_url(@book) }
      format.json
    end
  end

  private
    def book_params
      params.require(:book).permit(:published, :slug)
    end
end
