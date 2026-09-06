# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.2].define(version: 2026_03_17_235838) do
  create_table "accesses", force: :cascade do |t|
    t.integer "book_id", null: false
    t.datetime "created_at", null: false
    t.string "level", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["book_id"], name: "index_accesses_on_book_id"
    t.index ["user_id", "book_id"], name: "index_accesses_on_user_id_and_book_id", unique: true
    t.index ["user_id"], name: "index_accesses_on_user_id"
  end

  create_table "accounts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "custom_styles"
    t.string "join_code", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "action_text_markdowns", force: :cascade do |t|
    t.text "content", default: "", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "record_id", null: false
    t.string "record_type", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id"], name: "index_action_text_markdowns_on_record"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.string "slug"
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
    t.index ["slug"], name: "index_active_storage_attachments_on_slug", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "books", force: :cascade do |t|
    t.boolean "allow_view_selector", default: true, null: false
    t.string "author"
    t.datetime "created_at", null: false
    t.string "default_view", default: "grid", null: false
    t.boolean "everyone_access", default: true, null: false
    t.boolean "published", default: false, null: false
    t.string "slug", null: false
    t.string "subtitle"
    t.string "theme", default: "blue", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["published"], name: "index_books_on_published"
  end

  create_table "edits", force: :cascade do |t|
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.integer "leaf_id", null: false
    t.integer "leafable_id", null: false
    t.string "leafable_type", null: false
    t.datetime "updated_at", null: false
    t.index ["leaf_id"], name: "index_edits_on_leaf_id"
    t.index ["leafable_type", "leafable_id"], name: "index_edits_on_leafable"
  end

  create_table "leaves", force: :cascade do |t|
    t.integer "book_id", null: false
    t.datetime "created_at", null: false
    t.integer "leafable_id", null: false
    t.string "leafable_type", null: false
    t.float "position_score", null: false
    t.string "status", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["book_id"], name: "index_leaves_on_book_id"
    t.index ["leafable_type", "leafable_id"], name: "index_leafs_on_leafable"
  end

  create_table "pages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "pictures", force: :cascade do |t|
    t.string "caption"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "sections", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "theme"
    t.datetime "updated_at", null: false
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "last_active_at", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["token"], name: "index_sessions_on_token", unique: true
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "name", null: false
    t.string "password_digest", null: false
    t.integer "role", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["name"], name: "index_users_on_name", unique: true
  end

  add_foreign_key "accesses", "books"
  add_foreign_key "accesses", "users"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "edits", "leaves"
  add_foreign_key "leaves", "books"
  add_foreign_key "sessions", "users"

  # Virtual tables defined in this database.
  # Note that virtual tables may not work with other database engines. Be careful if changing database.
  create_virtual_table "leaf_search_index", "fts5", ["title", "content", "tokenize='porter'"]
end
