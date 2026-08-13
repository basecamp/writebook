class AddExternalIdToLeaves < ActiveRecord::Migration[8.2]
  def change
    add_column :leaves, :external_id, :string
    add_index :leaves, [ :book_id, :external_id ], unique: true
  end
end
