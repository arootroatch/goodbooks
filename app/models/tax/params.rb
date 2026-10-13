module Tax
  # One year's federal figures as the engine reads them (built by TaxParameters#to_tax_params).
  Params = Data.define(
    :standard_deduction_cents, :brackets, :ss_wage_base_cents, :se_earnings_bps, :ss_rate_bps, :medicare_rate_bps,
    :additional_medicare_bps, :additional_medicare_threshold_cents, :qbi_bps, :qbi_threshold_cents,
    :home_office_rate_cents, :home_office_max_sqft, :safe_harbor_high_agi_threshold_cents,
    :annual_additions_limit_cents, :elective_deferral_limit_cents
  )
end
