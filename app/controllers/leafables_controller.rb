class LeafablesController < ApplicationController
  allow_unauthenticated_access only: :show

  include SetBookLeaf

  before_action :ensure_editable, except: :show
  before_action :broadcast_being_edited_indicator, only: :update

  def new
    @leafable = new_leafable
  end

  def create
    @leaf = @book.press new_leafable, leaf_params
    position_new_leaf @leaf
  end

  def show
    respond_to do |format|
      format.html
      format.md { render markdown: @leaf.leafable }
    end
  end

  def edit
  end

  def update
    @leaf.edit leafable_params: leafable_params, leaf_params: leaf_params

    respond_to do |format|
      format.turbo_stream { render }
      format.html { head :no_content }
    end
  end

  def destroy
    @leaf.trashed!

    respond_to do |format|
      format.turbo_stream { render }
      format.html { redirect_to book_slug_url(@book) }
    end
  end

  private
    def leaf_params
      default_leaf_params.merge params.fetch(:leaf, {}).permit(:title)
    end

    def default_leaf_params
      { title: new_leafable.model_name.human }
    end

    def new_leafable
      raise NotImplementedError.new "Implement in subclass"
    end

    def leafable_params
      raise NotImplementedError.new "Implement in subclass"
    end

    def position_new_leaf(leaf)
      if position = params[:position]&.to_i
        leaf.move_to_position position
      end
    end

    def broadcast_being_edited_indicator
      Turbo::StreamsChannel.broadcast_render_later_to @leaf, :being_edited,
        partial: "leaves/being_edited_by", locals: { leaf: @leaf, user: Current.user }
    end
end
