if book.cover.attached?
  json.cover do
    json.checksum book.cover.blob.checksum
    json.filename book.cover.filename.to_s
    json.url rails_blob_path(book.cover)
  end
else
  json.cover nil
end
