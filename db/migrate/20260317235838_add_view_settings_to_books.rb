class AddViewSettingsToBooks < ActiveRecord::Migration[8.0]
  def change
    add_column :books, :default_view, :string, default: "grid", null: false
    add_column :books, :allow_view_selector, :boolean, default: true, null: false
  end
end
