# This migration comes from book_plugin (originally 20260501170500)
class CreateBookPluginFlashCards < ActiveRecord::Migration[8.1]
  def change
    json_type = connection.adapter_name.downcase.include?("postgres") ? :jsonb : :json

    create_table :book_plugin_flash_cards do |t|
      t.references :book, null: false, foreign_key: { to_table: :book_plugin_books }
      t.references :book_html, null: false, foreign_key: { to_table: :book_plugin_book_htmls }
      t.public_send(json_type, :areas_to_show, null: false, default: {})
      t.public_send(json_type, :items_to_remember, null: false, default: [])
      t.timestamps
    end
  end
end
