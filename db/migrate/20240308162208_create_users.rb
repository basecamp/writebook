class CreateUsers < ActiveRecord::Migration[7.2]
  def change
    create_table :users do |t|
      t.string :name, null: false, index: { unique: true }
      t.string :email_address, null: false, index: { unique: true }
      t.string :password_digest, null: false

      t.integer :role, null: false, default: 0
      t.boolean :active, default: true

      t.timestamps
    end
  end
end
