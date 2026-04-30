class CreateWordQuestionRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :word_question_records do |t|
      t.references :word_question, null: false, foreign_key: true
      t.string :picked_choice_token, null: false
      t.string :picked_choice_word, null: false
      t.boolean :is_correct, null: false, default: false

      t.timestamps
    end
  end
end
