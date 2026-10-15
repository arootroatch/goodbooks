class CreateTaxRecords < ActiveRecord::Migration[8.1]
  def change
    add_column :households, :irs_payment_url, :string, null: false, default: "https://www.irs.gov/payments/direct-pay"

    create_table :tax_years do |t|
      t.references :household, null: false, foreign_key: true
      t.integer :year, null: false
      t.integer :prior_year_total_tax_cents
      t.integer :prior_year_agi_cents
      t.timestamps
    end
    add_index :tax_years, %i[household_id year], unique: true

    create_table :estimated_payments do |t|
      t.references :tax_year, null: false, foreign_key: true
      t.integer :quarter, null: false
      t.date :paid_on, null: false
      t.integer :amount_cents, null: false
      t.references :debit, foreign_key: { to_table: :transactions, on_delete: :nullify }, index: { unique: true }
      t.timestamps
    end

    create_table :home_offices do |t|
      t.references :business, null: false, foreign_key: true
      t.integer :year, null: false
      t.string :calculation, null: false, default: "simplified"
      t.integer :office_sqft, null: false
      t.integer :home_sqft
      t.integer :rent_cents, null: false, default: 0
      t.integer :mortgage_interest_cents, null: false, default: 0
      t.integer :utilities_cents, null: false, default: 0
      t.integer :insurance_cents, null: false, default: 0
      t.integer :repairs_cents, null: false, default: 0
      t.integer :other_cents, null: false, default: 0
      t.integer :depreciation_cents, null: false, default: 0
      t.timestamps
    end
    add_index :home_offices, %i[business_id year], unique: true

    create_table :person_adjustments do |t|
      t.references :person, null: false, foreign_key: true
      t.integer :year, null: false
      t.integer :se_health_insurance_cents, null: false, default: 0
      t.integer :retirement_contribution_cents, null: false, default: 0
      t.string :retirement_plan
      t.timestamps
    end
    add_index :person_adjustments, %i[person_id year], unique: true
  end
end
