module SalesTax
  # Which period a new remittance pays by default (spec §4.4).
  module RemittancePeriod
    def self.default_for(business, posted_on, today: Date.current)
      profile = business.sales_tax_profile
      return unless profile && posted_on

      calendar = profile.calendar(today: [ posted_on, today ].max)
      ended = calendar.periods.select { _1.ends_on < posted_on }
      owed = SalesTax.build_reports(business, ended, today).find { _1.balance_cents.positive? }
      (owed&.period || ended.last || calendar.period_for(posted_on))&.starts_on
    end
  end
end
