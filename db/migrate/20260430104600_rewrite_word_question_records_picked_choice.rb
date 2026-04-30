# frozen_string_literal: true

class RewriteWordQuestionRecordsPickedChoice < ActiveRecord::Migration[8.1]
  def up
    add_column :word_question_records, :picked_choice_token, :string
    add_column :word_question_records, :picked_choice_word, :string

    execute <<~SQL.squish
      UPDATE word_question_records
      SET
        picked_choice_token = 'word:' || picked_word_id,
        picked_choice_word = words.word
      FROM words
      WHERE word_question_records.picked_word_id = words.id
    SQL

    change_column_null :word_question_records, :picked_choice_token, false
    change_column_null :word_question_records, :picked_choice_word, false

    remove_index :word_question_records, :picked_word_id
    remove_foreign_key :word_question_records, column: :picked_word_id
    remove_column :word_question_records, :picked_word_id
  end

  def down
    add_reference :word_question_records, :picked_word, foreign_key: { to_table: :words }

    execute <<~SQL.squish
      UPDATE word_question_records
      SET picked_word_id = CAST(SPLIT_PART(picked_choice_token, ':', 2) AS bigint)
      WHERE picked_choice_token LIKE 'word:%'
    SQL

    execute <<~SQL.squish
      UPDATE word_question_records
      SET picked_word_id = word_questions.word_id
      FROM word_questions
      WHERE word_question_records.word_question_id = word_questions.id
        AND word_question_records.picked_word_id IS NULL
    SQL

    change_column_null :word_question_records, :picked_word_id, false
    add_index :word_question_records, :picked_word_id

    remove_column :word_question_records, :picked_choice_token
    remove_column :word_question_records, :picked_choice_word
  end
end
