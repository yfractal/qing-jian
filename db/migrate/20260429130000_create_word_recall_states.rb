class CreateWordRecallStates < ActiveRecord::Migration[8.1]
  def change
    create_table :word_recall_states do |t|
      t.references :word, null: false, foreign_key: true, index: { unique: true }
      t.integer :remember_times, null: false, default: 0
      t.date :due_day

      t.timestamps
    end

    add_index :word_recall_states, :due_day

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          INSERT INTO word_recall_states (word_id, remember_times, due_day, created_at, updated_at)
          SELECT id, 0, DATE(created_at), CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
          FROM words
        SQL
      end
    end
  end
end
