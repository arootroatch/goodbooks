class CreateSalesTaxProfilesAndFilings < ActiveRecord::Migration[8.1]
  def change
    create_table :sales_tax_profiles do |t|
      t.references :business, null: false, foreign_key: true, index: { unique: true }
      t.string :tn_account_number
      t.string :filing_frequency, null: false, default: "quarterly"
      t.integer :default_rate_bps, null: false
      t.date :starts_on, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    create_table :sales_tax_filings do |t|
      t.references :business, null: false, foreign_key: true
      t.date :period_starts_on, null: false
      t.date :filed_on, null: false
      t.string :confirmation_number
      t.timestamps
    end
    add_index :sales_tax_filings, %i[business_id period_starts_on], unique: true
  end
end
