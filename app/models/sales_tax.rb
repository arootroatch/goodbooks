module SalesTax
  def self.reports_for(business, today: Date.current)
    profile = business.sales_tax_profile
    return [] unless profile

    build_reports(business, profile.calendar(today: today).periods, today)
  end

  def self.report_for(business, period, today: Date.current) = build_reports(business, [ period ], today).first

  def self.build_reports(business, periods, today)
    return [] if periods.empty?

    entries = Entries.for(business, periods.first.starts_on..periods.last.ends_on)
    filings = business.sales_tax_filings.index_by(&:period_starts_on)
    periods.map do |period|
      PeriodReport.new(period: period, deposits: entries.deposits, remittances: entries.remittances,
                       filing: filings[period.starts_on], today: today)
    end
  end
end
