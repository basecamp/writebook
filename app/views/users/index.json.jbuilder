json.join_url join_url(Current.account.join_code)
json.can_administer Current.user.can_administer?

json.users @users do |user|
  json.(user, :id, :name, :role)
  json.current user.current?
end
