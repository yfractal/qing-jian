# frozen_string_literal: true

class AddExampleSentenceToWords < ActiveRecord::Migration[8.1]
  def change
    add_column :words, :example_sentence, :text
  end
end
