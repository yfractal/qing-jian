class RewriteBookPluginBookHtmlsToLayout < ActiveRecord::Migration[8.1]
  def up
    json_type = connection.adapter_name.downcase.include?("postgres") ? :jsonb : :json
    add_column :book_plugin_book_htmls, :layout, json_type, null: false, default: {}
    remove_column :book_plugin_book_htmls, :html
  end

  def down
    add_column :book_plugin_book_htmls, :html, :text, null: false, default: ""
    remove_column :book_plugin_book_htmls, :layout
  end
end
