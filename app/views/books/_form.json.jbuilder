json.book do
  json.extract! book, :id, :title, :subtitle, :author, :theme, :everyone_access
  json.partial! "books/cover", book: book
end

json.users users do |user|
  json.extract! user, :id, :name

  if user == creating_user
    json.role "editor"
  else
    json.role book.role_for(user)
  end

  json.can_administer user.can_administer?
  json.current user.current?
end
