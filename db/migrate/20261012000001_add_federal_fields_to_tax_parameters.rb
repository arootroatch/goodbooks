class AddFederalFieldsToTaxParameters < ActiveRecord::Migration[8.1]
  def change
    change_table :tax_parameters, bulk: true do |t|
      t.integer :standard_deduction_mfj_cents
      t.json :brackets_mfj
      t.integer :ss_wage_base_cents
      t.integer :se_earnings_bps
      t.integer :ss_rate_bps
      t.integer :medicare_rate_bps
      t.integer :additional_medicare_bps
      t.integer :additional_medicare_threshold_mfj_cents
      t.integer :qbi_bps
      t.integer :qbi_threshold_mfj_cents
      t.integer :home_office_simplified_rate_cents
      t.integer :home_office_simplified_max_sqft
      t.integer :safe_harbor_high_agi_threshold_cents
      t.integer :annual_additions_limit_cents
      t.integer :elective_deferral_limit_cents
    end
  end
end
