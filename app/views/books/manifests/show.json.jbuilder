json.book do
  json.extract! @book, :id, :title, :subtitle, :author, :theme, :slug, :published
  json.fingerprint @book.fingerprint

  if @book.cover.attached?
    json.cover do
      json.checksum @book.cover.blob.checksum
      json.filename @book.cover.filename.to_s
      json.url rails_blob_path(@book.cover)
    end
  else
    json.cover nil
  end
end

json.leaves @leaves do |leaf|
  json.extract! leaf, :id, :title
  json.type leaf.leafable_type
  json.fingerprint leaf.fingerprint

  case leaf.leafable
  when Section
    json.theme leaf.leafable.theme
  when Picture
    if leaf.leafable.image.attached?
      json.image do
        json.checksum leaf.leafable.image.blob.checksum
        json.filename leaf.leafable.image.filename.to_s
        json.url rails_blob_path(leaf.leafable.image)
      end
    else
      json.image nil
    end
  end
end
