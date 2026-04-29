class CreateWordQuestionRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :word_question_records do |t|
      t.references :word_question, null: false, foreign_key: true
      t.bigint :picked_word_id, null: false
      t.boolean :is_correct, null: false, default: false

      t.timestamps
    end

    add_foreign_key :word_question_records, :words, column: :picked_word_id
    add_index :word_question_records, :picked_word_id
  end
end
