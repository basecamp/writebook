class BooksController < ApplicationController
  allow_unauthenticated_access only: %i[ index show ]

  before_action :ensure_index_is_not_empty, only: :index
  before_action :set_book, only: %i[ show edit update destroy ]
  before_action :set_users, only: %i[ new edit ]
  before_action :ensure_editable, only: %i[ edit update destroy ]

  def index
    @books = Book.accessable_or_published.ordered
  end

  def new
    @book = Book.new
  end

  def create
    book = Book.create! book_params
    update_accesses(book)

    redirect_to book_slug_url(book)
  end

  def show
    @leaves = @book.leaves.active.with_leafables.positioned

    respond_to do |format|
      format.html
      format.md do
        set_active_storage_url_options
        render plain: @book.to_markdown
      end
    end
  end

  def edit
  end

  def update
    @book.update(book_params)
    update_accesses(@book)
    remove_cover if params[:remove_cover] == "true"

    redirect_to book_slug_url(@book)
  end

  def destroy
    @book.destroy

    redirect_to root_url
  end

  private
    def set_book
      @book = Book.accessable_or_published.find params[:id]
    end

    def set_users
      @users = User.active.ordered
    end

    def ensure_editable
      head :forbidden unless @book.editable?
    end

    def ensure_index_is_not_empty
      if !signed_in? && Book.published.none?
        require_authentication
      end
    end

    def book_params
      params.require(:book).permit(:title, :subtitle, :author, :cover, :remove_cover, :everyone_access, :theme)
    end

    def update_accesses(book)
      editors = [ Current.user.id, *params[:editor_ids]&.map(&:to_i) ]
      readers = [ Current.user.id, *params[:reader_ids]&.map(&:to_i) ]

      book.update_access(editors: editors, readers: readers)
    end

    def remove_cover
      @book.cover.purge
    end
end
