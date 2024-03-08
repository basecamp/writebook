class CreateSessions < ActiveRecord::Migration[7.2]
  def change
    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: true, index: true
      t.string :token, null: false
      t.string :ip_address
      t.string :user_agent
      t.datetime :last_active_at, null: false

      t.timestamps
    end

    add_index :sessions, :token, unique: true
  end
end
