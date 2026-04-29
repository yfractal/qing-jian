# frozen_string_literal: true

class AddWordToWords < ActiveRecord::Migration[8.1]
  def up
    add_column :words, :word, :string

    execute <<~SQL.squish
      UPDATE words SET word = english_meaning WHERE word IS NULL
    SQL

    change_column_null :words, :word, false

    execute <<~SQL.squish
      CREATE UNIQUE INDEX index_words_on_lower_word ON words (LOWER(word))
    SQL
  end

  def down
    execute <<~SQL.squish
      DROP INDEX IF EXISTS index_words_on_lower_word
    SQL

    change_column_null :words, :word, true
    remove_column :words, :word
  end
end
