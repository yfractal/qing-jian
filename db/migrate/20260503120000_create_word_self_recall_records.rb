class CreateWordSelfRecallRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :word_self_recall_records do |t|
      t.references :word, null: false, foreign_key: true
      t.boolean :is_correct, null: false

      t.timestamps
    end
  end
end
