json.extract! @leaf, :id, :title
json.type @leaf.leafable_type
json.fingerprint @leaf.fingerprint

case @leaf.leafable
when Page
  json.body @leaf.leafable.markable
  json.record_gid @leaf.leafable.to_signed_global_id(
    expires_in: ActionText::Markdown::UPLOADS_SIGNED_ID_EXPIRY,
    for: ActionText::Markdown::UPLOADS_SIGNED_ID_PURPOSE
  ).to_s
when Section
  json.body @leaf.leafable.body
  json.theme @leaf.leafable.theme
when Picture
  json.caption @leaf.leafable.caption

  if @leaf.leafable.image.attached?
    json.image do
      json.checksum @leaf.leafable.image.blob.checksum
      json.filename @leaf.leafable.image.filename.to_s
      json.url rails_blob_path(@leaf.leafable.image)
    end
  else
    json.image nil
  end
end
