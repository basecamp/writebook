class PagesController < LeafablesController
  before_action :forget_reading_progress, except: :show

  private
    def forget_reading_progress
      cookies.delete "reading_progress_#{@book.id}"
    end

    def default_leaf_params
      { title: "Untitled" }
    end

    def new_leafable
      Page.new leafable_params
    end

    def leafable_params
      if leaf_document
        { body: leaf_document.body }
      else
        params.fetch(:page, {}).permit(:body)
      end
    end
end
