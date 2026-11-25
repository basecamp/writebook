class AddScopeToOauthTables < ActiveRecord::Migration[8.0]
  def change
    add_column :oauth_device_grants, :scope, :string, default: "read write", null: false
    add_column :oauth_refresh_tokens, :scope, :string, default: "read write", null: false
    add_column :oauth_access_tokens, :scope, :string, default: "read write", null: false
  end
end
