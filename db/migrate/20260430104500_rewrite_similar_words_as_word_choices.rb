# frozen_string_literal: true

class RewriteSimilarWordsAsWordChoices < ActiveRecord::Migration[8.1]
  def up
    add_reference :similar_words, :word_question, foreign_key: true
    add_column :similar_words, :word, :string
    add_column :similar_words, :english_meaning, :string
    add_column :similar_words, :chinese_meaning, :string

    execute <<~SQL.squish
      UPDATE similar_words
      SET
        word_question_id = similar_wordable_id,
        word = words.word,
        english_meaning = words.english_meaning,
        chinese_meaning = words.chinese_meaning
      FROM words
      WHERE similar_words.word_id = words.id
        AND similar_words.similar_wordable_type = 'WordQuestion'
    SQL

    execute <<~SQL.squish
      DELETE FROM similar_words
      WHERE word_question_id IS NULL
    SQL

    change_column_null :similar_words, :word_question_id, false
    change_column_null :similar_words, :word, false
    change_column_null :similar_words, :english_meaning, false
    change_column_null :similar_words, :chinese_meaning, false

    remove_index :similar_words, name: "index_similar_words_on_similar_wordable"
    remove_index :similar_words, :word_id
    remove_foreign_key :similar_words, :words
    remove_column :similar_words, :similar_wordable_id
    remove_column :similar_words, :similar_wordable_type
    remove_column :similar_words, :word_id
  end

  def down
    add_reference :similar_words, :similar_wordable, polymorphic: true
    add_reference :similar_words, :word, foreign_key: true

    execute <<~SQL.squish
      INSERT INTO words (word, english_meaning, chinese_meaning, created_at, updated_at)
      SELECT DISTINCT similar_words.word, similar_words.english_meaning, similar_words.chinese_meaning, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM similar_words
      WHERE NOT EXISTS (
        SELECT 1 FROM words WHERE LOWER(words.word) = LOWER(similar_words.word)
      )
    SQL

    execute <<~SQL.squish
      UPDATE similar_words
      SET
        similar_wordable_id = word_question_id,
        similar_wordable_type = 'WordQuestion',
        word_id = words.id
      FROM words
      WHERE LOWER(words.word) = LOWER(similar_words.word)
    SQL

    change_column_null :similar_words, :similar_wordable_id, false
    change_column_null :similar_words, :similar_wordable_type, false
    change_column_null :similar_words, :word_id, false

    remove_column :similar_words, :word_question_id
    remove_column :similar_words, :word
    remove_column :similar_words, :english_meaning
    remove_column :similar_words, :chinese_meaning
  end
end
