# frozen_string_literal: true

class AddTextAdjustmentsToBookPluginFlashCards < ActiveRecord::Migration[8.1]
  def change
    json_type = connection.adapter_name.downcase.include?("postgres") ? :jsonb : :json
    add_column :book_plugin_flash_cards, :text_adjustments, json_type, null: false, default: []
  end
end
