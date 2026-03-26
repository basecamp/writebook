class Books::ImportsController < ApplicationController
  include BookScoped

  before_action :ensure_editable

  def create
    imported_leaves = begin
      PdfImporter.new(@book, params[:pdf]&.tempfile).import
    rescue PdfImporter::InvalidPdfError, ArgumentError => e
      Rails.logger.error("PdfImporter failed: #{e.class}: #{e.message}")
      []
    end

    if imported_leaves.any?
      redirect_to book_slug_url(@book)
    else
      redirect_to book_slug_url(@book), alert: "Could not import PDF."
    end
  end
end
