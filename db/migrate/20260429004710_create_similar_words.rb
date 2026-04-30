class CreateSimilarWords < ActiveRecord::Migration[8.1]
  def change
    create_table :similar_words do |t|
      t.references :word_question, null: false, foreign_key: true
      t.string :word, null: false
      t.string :english_meaning, null: false
      t.string :chinese_meaning, null: false

      t.timestamps
    end
  end
end
