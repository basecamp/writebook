class CreateApiTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :api_tokens do |t|
      t.integer :user_id, null: false, index: true
      t.string :name, null: false
      t.string :token_digest, null: false, index: { unique: true }
      t.datetime :last_used_at
      t.timestamps
    end
  end
end
