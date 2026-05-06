# This migration comes from book_plugin (originally 20260506120000)
class AddVectorAdjustmentsToBookPluginFlashCards < ActiveRecord::Migration[8.1]
  def change
    json_type = connection.adapter_name.downcase.include?("postgres") ? :jsonb : :json
    add_column :book_plugin_flash_cards, :vector_adjustments, json_type, null: false, default: []
  end
end
