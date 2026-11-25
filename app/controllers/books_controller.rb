class BooksController < ApplicationController
  allow_unauthenticated_access only: %i[ index show ]
  allow_read_only_token_access only: %i[ index show ]

  before_action :ensure_index_is_not_empty, only: :index, unless: -> { request.format.json? }
  before_action :set_book, only: %i[ show edit update destroy ]
  before_action :set_users, only: %i[ new edit ]
  before_action :ensure_editable, only: %i[ edit update destroy ]

  def index
    @books = Book.accessable_or_published.with_attached_cover.ordered

    respond_to do |format|
      format.html
      format.json
    end
  end

  def new
    @book = Book.new
  end

  def create
    book = Book.new(book_params)

    if book.save
      update_accesses(book)

      respond_to do |format|
        format.html { redirect_to book_slug_url(book) }
        format.json { render json: { id: book.id, slug: book.slug, url: book_slug_url(book), fingerprint: book.fingerprint }, status: :created }
      end
    else
      render_errors book
    end
  end

  def show
    @leaves = @book.leaves.active.with_leafables.positioned

    respond_to do |format|
      format.html
      format.md
    end
  end

  def edit
  end

  def update
    respond_to do |format|
      format.html do
        @book.update(book_params)
        remove_cover if params[:remove_cover] == "true"
        update_accesses(@book)
        redirect_to book_slug_url(@book)
      end

      format.json do
        if @book.update_with_access(book_params, editors: given_ids(:editor_ids), readers: given_ids(:reader_ids))
          remove_cover if params[:remove_cover] == "true"
          render json: { id: @book.id, fingerprint: @book.fingerprint }
        else
          render_errors @book
        end
      end
    end
  end

  def destroy
    @book.destroy

    respond_to do |format|
      format.html { redirect_to root_url }
      format.json { head :no_content }
    end
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
      uploaded_files_only params.fetch(:book, {}).permit(:title, :subtitle, :author, :cover, :remove_cover, :everyone_access, :theme), :cover
    end

    def update_accesses(book)
      editors = [ Current.user.id, *Array(params[:editor_ids]).map(&:to_i) ]
      readers = [ Current.user.id, *Array(params[:reader_ids]).map(&:to_i) ]

      book.update_access(editors: editors, readers: readers)
    end

    def given_ids(key)
      [ Current.user.id, *Array(params[key]).map(&:to_i) ] if params.key?(key)
    end

    def render_errors(book)
      respond_to do |format|
        format.html { head :unprocessable_entity }
        format.json { render json: { errors: book.errors.full_messages }, status: :unprocessable_entity }
      end
    end

    def remove_cover
      @book.cover.purge
    end
end
