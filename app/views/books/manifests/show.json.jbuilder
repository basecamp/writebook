json.book do
  json.extract! @book, :id, :title, :subtitle, :author, :theme, :slug, :published
  json.fingerprint @book.fingerprint
  json.editable can_edit?(@book)
  json.partial! "books/cover", book: @book
end

json.leaves @leaves do |leaf|
  json.extract! leaf, :id, :title
  json.type leaf.leafable_type
  json.fingerprint leaf.fingerprint
  json.word_count leaf.leafable.word_count
  json.preview leaf.leafable.text_preview

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
