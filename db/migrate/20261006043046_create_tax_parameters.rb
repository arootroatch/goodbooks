class CreateTaxParameters < ActiveRecord::Migration[8.1]
  def change
    create_table :tax_parameters do |t|
      t.integer :year, null: false, index: { unique: true }
      t.integer :standard_mileage_rate_tenth_cents, null: false
      t.timestamps
    end
  end
end
