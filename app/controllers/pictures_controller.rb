class PicturesController < LeafablesController
  private
    def new_leafable
      Picture.new leafable_params
    end

    def leafable_params
      uploaded_files_only params.fetch(:picture, {}).permit(:image, :caption), :image
    end
end
