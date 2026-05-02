# This migration comes from book_plugin (originally 20260502204000)
class CreateBookPluginFlashCardRecallStates < ActiveRecord::Migration[8.1]
  def change
    create_table :book_plugin_flash_card_recall_states do |t|
      t.references :flash_card, null: false, foreign_key: { to_table: :book_plugin_flash_cards }, index: { unique: true }
      t.integer :remember_times, null: false, default: 0
      t.date :due_day

      t.timestamps
    end

    add_index :book_plugin_flash_card_recall_states, :due_day
  end
end
