class CreateBookPluginFlashCardRecallRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :book_plugin_flash_card_recall_records do |t|
      t.references :flash_card, null: false, foreign_key: { to_table: :book_plugin_flash_cards }
      t.boolean :is_correct, null: false

      t.timestamps
    end
  end
end
