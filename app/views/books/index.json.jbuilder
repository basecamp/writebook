json.array! @books do |book|
  json.extract! book, :id, :title, :subtitle, :author, :theme, :slug, :published, :updated_at
  json.editable signed_in? && book.editable?
  json.url book_slug_url(book)
  json.markdown_url book_slug_url(book, format: :md)
  json.manifest_url book_manifest_url(book, format: :json)
  json.search_url book_search_url(book, format: :json)

  if book.cover.attached?
    json.cover do
      json.checksum book.cover.blob.checksum
      json.url rails_blob_path(book.cover)
    end
  else
    json.cover nil
  end
end
