require "rails_helper"

RSpec.describe Reports::InvoiceAgingCsv do
  it "writes bucket, invoice, days past due, and outstanding" do
    as_of = Date.new(2026, 10, 6)
    row = Reports::InvoiceAging::Row.new(invoice_id: 1, number: "INV-1", client_name: "Acme", business_name: "Pat Consulting",
                                         due_date: as_of - 45, outstanding_cents: 9_500)
    report = Reports::InvoiceAging.new([ row ], as_of: as_of)
    rows = CSV.parse(described_class.generate(report, as_of: as_of))
    expect(rows).to eq([ Reports::InvoiceAgingCsv::HEADERS, [ "31–60 days", "INV-1", "Pat Consulting", "Acme", "2026-08-22", "45", "95.00" ] ])
  end
end
