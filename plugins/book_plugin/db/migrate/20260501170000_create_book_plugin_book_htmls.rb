class CreateBookPluginBookHtmls < ActiveRecord::Migration[8.1]
  def change
    create_table :book_plugin_book_htmls do |t|
      t.references :book, null: false, foreign_key: { to_table: :book_plugin_books }
      t.integer :page_number, null: false
      t.text :html, null: false
      t.timestamps
    end

    add_index :book_plugin_book_htmls, [:book_id, :page_number], unique: true
  end
end
