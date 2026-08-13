json.array! @leaves.each_with_index.to_a do |(leaf, index)|
  json.id leaf.id
  json.leafable_type leaf.leafable_type
  json.title leaf.title
  json.slug leaf.slug
  json.position index
  json.external_id leaf.external_id
  json.url leafable_slug_url(leaf)
end
