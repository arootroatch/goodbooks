require "rails_helper"

RSpec.describe Reports::SalesTaxPeriodCsv do
  it "writes deposits, remittances, and the summary" do
    business = create(:business)
    create(:sales_tax_profile, business: business)
    account = create(:account, business: business, name: "Checking")
    sales = create(:category, :income, business: business)
    create(:transaction, account: account, category: sales, payee: "STRIPE", amount_cents: 97_070, processor_fee_cents: 2_930,
                         sales_tax_cents: 8_467, posted_on: Date.new(2026, 2, 6))
    period = business.sales_tax_profile.calendar(today: Date.new(2026, 5, 1)).periods.first
    rows = CSV.parse(described_class.generate(SalesTax.report_for(business, period, today: Date.new(2026, 5, 1))))
    expect(rows.first).to eq(described_class::HEADERS)
    expect(rows.second).to eq([ "2026-02-06", "Taxable sale", "Checking", "STRIPE", "1000.00", "29.30", "84.67", "0.00", nil ])
    expect(rows).to include([ "Tax collected", "84.67" ], [ "Balance owed", "84.67" ], [ "Status", "overdue" ])
  end
end
