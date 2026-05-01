# This migration comes from book_plugin (originally 20260501083000)
class CreateBookPluginBooks < ActiveRecord::Migration[8.1]
  def change
    create_table :book_plugin_books do |t|
      t.string :title, null: false
      t.text :description

      t.timestamps
    end
  end
end
