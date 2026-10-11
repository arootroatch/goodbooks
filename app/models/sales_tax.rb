module SalesTax
  Summary = Data.define(:next_report, :owed_cents, :overdue_reports) do
    def next_due_on = next_report&.period&.due_on
  end

  def self.summary_for(business, today: Date.current)
    return unless business.collects_sales_tax?

    reports = reports_for(business, today: today)
    Summary.new(
      next_report: reports.reject(&:filed?).select { _1.period.due_on >= today }.min_by { _1.period.due_on },
      owed_cents: reports.reject(&:paid?).sum { [ _1.balance_cents, 0 ].max },
      overdue_reports: reports.select { _1.status == "overdue" }
    )
  end

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
