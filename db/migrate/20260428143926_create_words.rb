class CreateWords < ActiveRecord::Migration[8.1]
  def change
    create_table :words do |t|
      t.string :chinese_meaning
      t.string :english_meaning

      t.timestamps
    end
  end
end
