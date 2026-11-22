json.array! @books do |book|
  json.extract! book, :id, :title, :subtitle, :author, :slug, :published, :updated_at
  json.url book_slug_url(book)
  json.markdown_url book_slug_url(book, format: :md)
  json.manifest_url book_manifest_url(book, format: :json)
  json.search_url book_search_url(book, format: :json)
end
