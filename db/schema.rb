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

ActiveRecord::Schema[8.1].define(version: 2026_04_30_122940) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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

  create_table "words", force: :cascade do |t|
    t.string "chinese_meaning"
    t.datetime "created_at", null: false
    t.string "english_meaning"
    t.string "pronunciation"
    t.datetime "updated_at", null: false
    t.string "word", null: false
    t.index "lower((word)::text)", name: "index_words_on_lower_word", unique: true
  end

  add_foreign_key "similar_words", "word_questions"
  add_foreign_key "word_question_records", "word_questions"
  add_foreign_key "word_questions", "words"
  add_foreign_key "word_recall_states", "words"
end
