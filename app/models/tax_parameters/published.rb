# Federal figures as published, keyed by tax year. Seeds and the demo copy them; the household owner can edit the stored row.
class TaxParameters
  module Published
    YEARS = {
      2026 => {
        standard_mileage_rate_tenth_cents: 725, # IRS Notice 2026 standard mileage rates: 72.5¢/mile
        standard_deduction_mfj_cents: 3_220_000, # Rev. Proc. 2025-32: $32,200 MFJ
        brackets_mfj: [ # Rev. Proc. 2025-32, MFJ
          { "floor_cents" => 0, "rate_bps" => 1000 },
          { "floor_cents" => 2_480_000, "rate_bps" => 1200 },
          { "floor_cents" => 10_080_000, "rate_bps" => 2200 },
          { "floor_cents" => 21_140_000, "rate_bps" => 2400 },
          { "floor_cents" => 40_355_000, "rate_bps" => 3200 },
          { "floor_cents" => 51_245_000, "rate_bps" => 3500 },
          { "floor_cents" => 76_870_000, "rate_bps" => 3700 }
        ],
        ss_wage_base_cents: 18_450_000, # SSA 2026 COLA fact sheet: $184,500
        se_earnings_bps: 9235, # IRC §1402(a)(12)
        ss_rate_bps: 1240, # IRC §1401(a)
        medicare_rate_bps: 290, # IRC §1401(b)(1)
        additional_medicare_bps: 90, # IRC §1401(b)(2)
        additional_medicare_threshold_mfj_cents: 25_000_000, # IRC §1401(b)(2)(A), not indexed
        qbi_bps: 2000, # IRC §199A(a)
        qbi_threshold_mfj_cents: 40_350_000, # Rev. Proc. 2025-32: $403,500 MFJ
        home_office_simplified_rate_cents: 500, # Rev. Proc. 2013-13
        home_office_simplified_max_sqft: 300, # Rev. Proc. 2013-13
        safe_harbor_high_agi_threshold_cents: 15_000_000, # IRC §6654(d)(1)(C)
        annual_additions_limit_cents: 7_200_000, # IRS 2026 retirement plan COLA notice, §415(c)
        elective_deferral_limit_cents: 2_450_000 # IRS 2026 retirement plan COLA notice, §402(g)
      }
    }.freeze

    def self.fetch(year) = YEARS.fetch(year)
  end
end
