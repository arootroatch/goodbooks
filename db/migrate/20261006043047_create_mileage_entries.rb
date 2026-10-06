class CreateMileageEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :mileage_entries do |t|
      t.references :business, null: false, foreign_key: true
      t.date :driven_on, null: false
      t.string :purpose, null: false
      t.string :from_location
      t.string :to_location
      t.integer :miles_tenths, null: false
      t.boolean :round_trip, null: false, default: false
      t.timestamps
    end
    add_index :mileage_entries, :driven_on
  end
end
