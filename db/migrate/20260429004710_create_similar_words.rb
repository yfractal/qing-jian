class CreateSimilarWords < ActiveRecord::Migration[8.1]
  def change
    create_table :similar_words do |t|
      t.references :similar_wordable, polymorphic: true, null: false
      t.references :word, null: false, foreign_key: true

      t.timestamps
    end
  end
end
