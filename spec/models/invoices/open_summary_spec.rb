require "rails_helper"

RSpec.describe Invoices::OpenSummary do
  let(:today) { Date.new(2026, 10, 10) }
  let(:business) { create(:business) }

  def invoice(due:, amount: 100_000, status: "sent", **attrs)
    create(:invoice, business:, due_date: due, issue_date: due - 30, amount_cents: amount, status:, **attrs)
  end

  it "splits sent invoices with money owed into overdue and not yet due, oldest due date first" do
    late = invoice(due: today - 45)
    later = invoice(due: today - 3, amount: 50_000)
    soon = invoice(due: today + 5)
    today_due = invoice(due: today)
    invoice(due: today - 10, status: "draft")
    invoice(due: today - 10, status: "void")
    create(:invoice_payment, invoice: invoice(due: today - 20, amount: 30_000))

    summary = described_class.for(Invoice.all, today:)
    expect(summary.overdue.invoices).to eq([ late, later ])
    expect(summary.overdue.total_cents).to eq(150_000)
    expect(summary.upcoming.invoices).to eq([ today_due, soon ])
    expect(summary.upcoming.total_cents).to eq(200_000)
    expect(summary.outstanding_cents).to eq(350_000)
  end

  it "counts only what is still owed on partly paid invoices" do
    partly = invoice(due: today - 5)
    create(:invoice_payment, invoice: partly, amount_cents: 40_000)
    summary = described_class.for(Invoice.all, today:)
    expect(summary.overdue.total_cents).to eq(60_000)
  end

  it "is empty with no open invoices" do
    summary = described_class.for(Invoice.all, today:)
    expect(summary.overdue.invoices).to be_empty
    expect(summary.outstanding_cents).to eq(0)
  end
end
