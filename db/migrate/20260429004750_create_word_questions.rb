class CreateWordQuestions < ActiveRecord::Migration[8.1]
  def change
    create_table :word_questions do |t|
      t.references :word, null: false, foreign_key: true

      t.timestamps
    end
  end
end
