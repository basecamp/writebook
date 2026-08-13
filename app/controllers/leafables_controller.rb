class LeafablesController < ApplicationController
  allow_unauthenticated_access only: :show
  allow_bearer_key_access only: %i[ show create update destroy ]

  include SetBookLeaf

  before_action :ensure_editable, except: :show
  before_action :broadcast_being_edited_indicator, only: :update, unless: -> { api_request? }

  rescue_from Leaf::Document::Malformed do |error|
    render plain: error.message, status: :unprocessable_entity
  end

  def new
    @leafable = new_leafable
  end

  def create
    if api_request? && @leaf = leaf_with_external_id
      revise_leaf
      render_leaf
    else
      @leaf = @book.press new_leafable, leaf_params.with_defaults(default_leaf_params)
      position_leaf
      render_leaf status: :created if api_request?
    end
  end

  def show
    respond_to do |format|
      format.html
      format.md
    end
  end

  def edit
  end

  def update
    revise_leaf

    respond_to do |format|
      format.turbo_stream { render }
      format.html { head :no_content }
      format.any(:md, :json) { render_leaf }
    end
  end

  def destroy
    @leaf.trashed!

    respond_to do |format|
      format.turbo_stream { render }
      format.html { redirect_to book_slug_url(@book) }
      format.any(:md, :json) { head :no_content }
    end
  end

  private
    def api_request?
      request.format.md? || request.format.json?
    end

    def leaf_document
      @leaf_document ||= Leaf::Document.parse(request.raw_post) if request.format.md?
    end

    def external_id
      leaf_document ? leaf_document.external_id : params[:external_id].presence
    end

    def leaf_with_external_id
      @book.leaves.find_by(external_id: external_id) if external_id
    end

    def revise_leaf
      @leaf.active! if @leaf.trashed?
      @leaf.edit leafable_params: leafable_params, leaf_params: leaf_params
      position_leaf
    end

    def position_leaf
      if position = requested_position
        @leaf.move_to_position position
      end
    end

    def requested_position
      leaf_document ? leaf_document.position : params[:position]&.to_i
    end

    def render_leaf(status: :ok)
      respond_to do |format|
        format.any(:md, :json) { render :show, status: status }
      end
    end

    def leaf_params
      if leaf_document
        { title: leaf_document.title, external_id: leaf_document.external_id }.compact
      else
        params.fetch(:leaf, {}).permit(:title).to_h.symbolize_keys.merge({ external_id: external_id }.compact)
      end
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

    def broadcast_being_edited_indicator
      Turbo::StreamsChannel.broadcast_render_later_to @leaf, :being_edited,
        partial: "leaves/being_edited_by", locals: { leaf: @leaf, user: Current.user }
    end
end
