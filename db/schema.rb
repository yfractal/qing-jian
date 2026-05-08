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

ActiveRecord::Schema[8.1].define(version: 2026_05_07_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
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

  create_table "book_plugin_book_htmls", force: :cascade do |t|
    t.bigint "book_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "layout", default: {}, null: false
    t.integer "page_number", null: false
    t.datetime "updated_at", null: false
    t.index ["book_id", "page_number"], name: "index_book_plugin_book_htmls_on_book_id_and_page_number", unique: true
    t.index ["book_id"], name: "index_book_plugin_book_htmls_on_book_id"
  end

  create_table "book_plugin_books", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "title", null: false
    t.datetime "updated_at", null: false
  end

  create_table "book_plugin_flash_card_recall_records", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "flash_card_id", null: false
    t.boolean "is_correct", null: false
    t.datetime "updated_at", null: false
    t.index ["flash_card_id"], name: "index_book_plugin_flash_card_recall_records_on_flash_card_id"
  end

  create_table "book_plugin_flash_card_recall_states", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "due_day"
    t.bigint "flash_card_id", null: false
    t.integer "remember_times", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["due_day"], name: "index_book_plugin_flash_card_recall_states_on_due_day"
    t.index ["flash_card_id"], name: "index_book_plugin_flash_card_recall_states_on_flash_card_id", unique: true
  end

  create_table "book_plugin_flash_cards", force: :cascade do |t|
    t.jsonb "areas_to_show", default: {}, null: false
    t.bigint "book_html_id", null: false
    t.bigint "book_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "items_to_remember", default: [], null: false
    t.datetime "updated_at", null: false
    t.jsonb "vector_adjustments", default: [], null: false
    t.index ["book_html_id"], name: "index_book_plugin_flash_cards_on_book_html_id"
    t.index ["book_id"], name: "index_book_plugin_flash_cards_on_book_id"
  end

  create_table "similar_words", force: :cascade do |t|
    t.string "chinese_meaning", null: false
    t.datetime "created_at", null: false
    t.string "english_meaning", null: false
    t.datetime "updated_at", null: false
    t.string "word", null: false
    t.bigint "word_question_id", null: false
    t.index ["word_question_id"], name: "index_similar_words_on_word_question_id"
  end

  create_table "word_question_records", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "is_correct", default: false, null: false
    t.string "picked_choice_token", null: false
    t.string "picked_choice_word", null: false
    t.datetime "updated_at", null: false
    t.bigint "word_question_id", null: false
    t.index ["word_question_id"], name: "index_word_question_records_on_word_question_id"
  end

  create_table "word_questions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "word_id", null: false
    t.index ["word_id"], name: "index_word_questions_on_word_id"
  end

  create_table "word_recall_states", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "due_day"
    t.integer "remember_times", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "word_id", null: false
    t.index ["due_day"], name: "index_word_recall_states_on_due_day"
    t.index ["word_id"], name: "index_word_recall_states_on_word_id", unique: true
  end

  create_table "word_self_recall_records", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "is_correct", null: false
    t.datetime "updated_at", null: false
    t.bigint "word_id", null: false
    t.index ["word_id"], name: "index_word_self_recall_records_on_word_id"
  end

  create_table "words", force: :cascade do |t|
    t.string "chinese_meaning"
    t.datetime "created_at", null: false
    t.string "english_meaning"
    t.text "example_sentence"
    t.string "pronunciation"
    t.datetime "updated_at", null: false
    t.string "word", null: false
    t.index "lower((word)::text)", name: "index_words_on_lower_word", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "book_plugin_book_htmls", "book_plugin_books", column: "book_id"
  add_foreign_key "book_plugin_flash_card_recall_records", "book_plugin_flash_cards", column: "flash_card_id"
  add_foreign_key "book_plugin_flash_card_recall_states", "book_plugin_flash_cards", column: "flash_card_id"
  add_foreign_key "book_plugin_flash_cards", "book_plugin_book_htmls", column: "book_html_id"
  add_foreign_key "book_plugin_flash_cards", "book_plugin_books", column: "book_id"
  add_foreign_key "similar_words", "word_questions"
  add_foreign_key "word_question_records", "word_questions"
  add_foreign_key "word_questions", "words"
  add_foreign_key "word_recall_states", "words"
  add_foreign_key "word_self_recall_records", "words"
end
