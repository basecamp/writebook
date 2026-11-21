json.query params[:q]

json.results @leaves do |leaf|
  json.extract! leaf, :id, :title
  json.type leaf.leafable_type
  json.book do
    json.extract! leaf.book, :id, :title
  end
  json.snippet search_result_text(leaf.content_match)
  json.url leafable_slug_url(leaf)
  json.markdown_url leafable_slug_url(leaf, format: :md)
end
