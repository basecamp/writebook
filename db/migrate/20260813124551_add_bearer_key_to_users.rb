class AddBearerKeyToUsers < ActiveRecord::Migration[8.2]
  def up
    add_column :users, :bearer_key, :string
    add_index :users, :bearer_key, unique: true

    User.find_each(&:regenerate_bearer_key)
  end

  def down
    remove_column :users, :bearer_key
  end
end
