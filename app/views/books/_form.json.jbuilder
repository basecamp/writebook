json.book do
  json.extract! book, :id, :title, :subtitle, :author, :theme, :everyone_access

  if book.cover.attached?
    json.cover do
      json.checksum book.cover.blob.checksum
      json.url rails_blob_path(book.cover)
    end
  else
    json.cover nil
  end
end

json.users users do |user|
  json.extract! user, :id, :name

  if book.editable?(user: user) || user == creating_user || user.can_administer?
    json.role "editor"
  elsif book.accessable?(user: user)
    json.role "reader"
  else
    json.role "none"
  end

  json.administrator user.can_administer?
  json.current user.current?
end
