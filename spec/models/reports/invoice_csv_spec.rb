require "rails_helper"

RSpec.describe Reports::InvoiceCsv do
  it "writes one row per invoice with money as plain decimals and neutralized text" do
    business = create(:business, name: "Pat Consulting")
    client = create(:client, business: business, name: "=HYPERLINK(\"x\")")
    invoice = create(:invoice, business: business, client: client, number: "INV-1", amount_cents: 120_000,
                               issue_date: Date.new(2026, 9, 1), due_date: Date.new(2026, 9, 30), description: "+cmd")
    create(:invoice_payment, invoice: invoice, amount_cents: 20_000)

    rows = CSV.parse(described_class.generate([ invoice.reload ], today: Date.new(2026, 10, 6)))
    expect(rows.first).to eq(Reports::InvoiceCsv::HEADERS)
    expect(rows.second).to eq([ "INV-1", "Pat Consulting", "'=HYPERLINK(\"x\")", "2026-09-01", "2026-09-30",
                                "1200.00", "200.00", "1000.00", "overdue", nil, "'+cmd" ])
  end
end
