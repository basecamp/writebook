json.book do
  json.extract! @book, :id, :title, :subtitle, :author, :theme, :slug, :published
  json.fingerprint @book.fingerprint
  json.editable signed_in? && @book.editable?

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
  when Page
    json.word_count leaf.leafable.body.content.to_s.split.size
    json.preview leaf.leafable.text_preview.truncate(280)
  when Section
    json.theme leaf.leafable.theme
    json.word_count nil
    json.preview leaf.leafable.body.to_s.squish.truncate(280)
  when Picture
    json.word_count nil
    json.preview nil

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
