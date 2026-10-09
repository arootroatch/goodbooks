require "rails_helper"

RSpec.describe SalesTax::Entries do
  let(:business) { create(:business) }
  let!(:profile) { create(:sales_tax_profile, business: business) }
  let(:account) { create(:account, business: business) }
  let(:sales) { create(:category, :income, business: business, name: "Sales") }
  let(:consulting) { create(:category, :income, business: business, name: "Consulting", sales_tax_treatment: "exempt") }
  let(:interest) { create(:category, business: business, name: "Interest", kind: "income", schedule_c_line: "6") }
  let(:remittance) { business.categories.sales_tax_remittance.sole }
  let(:q2) { Date.new(2026, 4, 1)..Date.new(2026, 6, 30) }

  it "loads taxable and exempt deposits in range with gross and total tax" do
    taxed = create(:transaction, account: account, category: sales, amount_cents: 97_070, processor_fee_cents: 2_930,
                                 sales_tax_cents: 8_467, posted_on: Date.new(2026, 4, 1))
    create(:transaction, account: account, category: consulting, amount_cents: 50_000, posted_on: Date.new(2026, 6, 30))
    create(:transaction, account: account, category: interest, amount_cents: 300, posted_on: Date.new(2026, 5, 1))
    create(:transaction, account: account, category: sales, amount_cents: 1_000, posted_on: Date.new(2026, 7, 1))
    create(:transaction, account: account, category: sales, amount_cents: 1_000, posted_on: Date.new(2026, 5, 1), excluded: true)
    create(:transaction, account: account, amount_cents: 1_000, posted_on: Date.new(2026, 5, 1))
    invoice = create(:invoice, business: business, amount_cents: 10_925, sales_tax_cents: 925)
    create(:invoice_payment, invoice: invoice, amount_cents: 10_925, sales_tax_cents: 925,
                             deposit: create(:transaction, account: account, category: sales, amount_cents: 10_925, posted_on: Date.new(2026, 5, 2)))

    deposits = described_class.for(business, q2).deposits
    expect(deposits.map { [ _1.treatment, _1.gross_cents, _1.total_tax_cents ] })
      .to eq([ [ "taxable", 100_000, 8_467 ], [ "taxable", 10_925, 925 ], [ "exempt", 50_000, 0 ] ])
    expect(deposits.first.source).to eq(taxed)
  end

  it "loads remittances by the period they pay, not the date they were paid" do
    create(:transaction, account: account, category: remittance, amount_cents: -8_000, posted_on: Date.new(2026, 7, 15),
                         sales_tax_period_starts_on: Date.new(2026, 4, 1))
    remittances = described_class.for(business, q2).remittances
    expect(remittances.map { [ _1.amount_cents, _1.period_starts_on ] }).to eq([ [ -8_000, Date.new(2026, 4, 1) ] ])
  end

  it "feeds whole-calendar period reports" do
    create(:transaction, account: account, category: sales, amount_cents: 10_925, sales_tax_cents: 925, posted_on: Date.new(2026, 2, 3))
    reports = SalesTax.reports_for(business, today: Date.new(2026, 5, 1))
    expect(reports.map { [ _1.period.label, _1.tax_collected_cents, _1.status ] }).to eq([ [ "Q1 2026", 925, "overdue" ], [ "Q2 2026", 0, "open" ] ])
    expect(SalesTax.reports_for(create(:business))).to eq([])
  end
end
