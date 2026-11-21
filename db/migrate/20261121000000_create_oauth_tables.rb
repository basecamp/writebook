class CreateOauthTables < ActiveRecord::Migration[8.0]
  def change
    create_table :oauth_device_grants do |t|
      t.string :device_code_digest, null: false, index: { unique: true }
      t.string :user_code, null: false, index: { unique: true }
      t.string :status, null: false, default: "pending"
      t.integer :user_id
      t.datetime :consumed_at
      t.datetime :last_polled_at
      t.datetime :expires_at, null: false
      t.timestamps
    end

    create_table :oauth_refresh_tokens do |t|
      t.string :token_digest, null: false, index: { unique: true }
      t.integer :user_id, null: false, index: true
      t.string :family_id, null: false, index: true
      t.integer :replaced_by_id
      t.datetime :rotated_at
      t.text :successor_raw_token
      t.datetime :revoked_at
      t.datetime :expires_at, null: false
      t.timestamps
    end

    create_table :oauth_access_tokens do |t|
      t.string :token_digest, null: false, index: { unique: true }
      t.integer :user_id, null: false, index: true
      t.integer :refresh_token_id, index: true
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.datetime :expires_at, null: false
      t.timestamps
    end
  end
end
