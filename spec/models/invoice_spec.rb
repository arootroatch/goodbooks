require "rails_helper"

RSpec.describe Invoice do
  let(:business) { create(:business) }
  let(:today) { Date.new(2026, 10, 6) }

  describe "validation" do
    it "keeps numbers unique within a business only" do
      create(:invoice, business: business, number: "INV-1")
      expect(build(:invoice, business: business, number: "INV-1")).not_to be_valid
      expect(build(:invoice, number: "INV-1")).to be_valid
    end

    it "requires the due date on or after the issue date" do
      invoice = build(:invoice, issue_date: Date.new(2026, 2, 1), due_date: Date.new(2026, 1, 31))
      expect(invoice).not_to be_valid
      expect(invoice.errors[:due_date]).to include("can't be before the issue date")
      expect(build(:invoice, issue_date: Date.new(2026, 2, 1), due_date: Date.new(2026, 2, 1))).to be_valid
    end

    it "requires the client to be in the same business" do
      invoice = build(:invoice, business: business, client: create(:client))
      expect(invoice).not_to be_valid
      expect(invoice.errors[:client]).to include("must belong to this business")
    end

    it "parses typed amounts and rejects zero, negative, and junk" do
      expect(build(:invoice, amount: "$1,200.00").amount_cents).to eq(120_000)
      expect(build(:invoice, amount: "1,200").amount_cents).to eq(120_000)
      %w[0 -5 abc].each { |input| expect(build(:invoice, amount: input)).not_to be_valid, "accepted #{input}" }
    end

    it "can't drop below what has been paid" do
      payment = create(:invoice_payment, invoice: create(:invoice, business: business), amount_cents: 50_000)
      invoice = payment.invoice
      invoice.amount_cents = 49_999
      expect(invoice).not_to be_valid
      expect(invoice.errors[:amount]).to include("can't be less than the $500.00 already paid")
    end
  end

  describe "derived status" do
    it "is overdue only after the due date" do
      expect(build(:invoice, due_date: today).display_status(today)).to eq("sent")
      overdue = build(:invoice, due_date: today - 1)
      expect(overdue.display_status(today)).to eq("overdue")
      expect(overdue.days_past_due(today)).to eq(1)
      expect(build(:invoice, due_date: today).days_past_due(today)).to eq(0)
    end

    it "is partial when sent with some payment" do
      payment = create(:invoice_payment, invoice: create(:invoice, due_date: today + 10), amount_cents: 20_000)
      expect(payment.invoice.reload.display_status(today)).to eq("partial")
      expect(payment.invoice.outstanding_cents).to eq(100_000)
    end

    it "never shows drafts, paid, or void invoices as overdue" do
      %w[draft paid void].each do |status|
        expect(build(:invoice, status: status, due_date: today - 30).display_status(today)).to eq(status)
      end
    end
  end

  describe "#apply_event" do
    it "moves draft → sent, draft/sent → void, void → sent" do
      invoice = create(:invoice, status: "draft")
      expect(invoice.apply_event("mark_sent")).to be(true)
      expect(invoice.reload).to be_sent
      expect(invoice.apply_event("void")).to be(true)
      expect(invoice.reload).to be_void
      expect(invoice.apply_event("reopen")).to be(true)
      expect(invoice.reload).to be_sent
    end

    it "refuses events that don't apply to the current status" do
      invoice = create(:invoice, status: "sent")
      expect(invoice.apply_event("mark_sent")).to be(false)
      expect(invoice.errors[:base]).to include("This invoice can't be marked sent while it is sent.")
      expect(invoice.reload).to be_sent
    end

    it "refuses to void an invoice that has payments" do
      payment = create(:invoice_payment, amount_cents: 10_000)
      invoice = payment.invoice
      expect(invoice.apply_event("void")).to be(false)
      expect(invoice.errors[:base]).to include("Unlink its payments before voiding this invoice.")
      expect(invoice.reload).to be_sent
    end
  end

  describe "#sync_payment_status!" do
    it "marks paid on the latest deposit date when fully paid, and reverts when not" do
      invoice = create(:invoice, business: business, amount_cents: 100_000)
      first = create(:invoice_payment, invoice: invoice, amount_cents: 40_000)
      first.deposit.update!(posted_on: Date.new(2026, 3, 1))
      second = create(:invoice_payment, invoice: invoice, amount_cents: 60_000)
      second.deposit.update!(posted_on: Date.new(2026, 3, 9))

      invoice.sync_payment_status!
      expect(invoice.reload).to be_paid
      expect(invoice.paid_on).to eq(Date.new(2026, 3, 9))

      second.destroy!
      invoice.sync_payment_status!
      expect(invoice.reload).to be_sent
      expect(invoice.paid_on).to be_nil
    end

    it "leaves drafts and void invoices alone" do
      invoice = create(:invoice, status: "draft")
      invoice.sync_payment_status!
      expect(invoice.reload).to be_draft
    end
  end

  it "can't be destroyed while it has payments" do
    payment = create(:invoice_payment)
    expect(payment.invoice.destroy).to be(false)
    expect(Invoice.exists?(payment.invoice_id)).to be(true)
  end

  describe "pdf" do
    it "accepts a PDF" do
      invoice = build(:invoice)
      invoice.pdf.attach(io: file_fixture("invoice.pdf").open, filename: "invoice.pdf")
      expect(invoice).to be_valid
    end

    it "rejects other file types" do
      invoice = build(:invoice)
      invoice.pdf.attach(io: file_fixture("checking.csv").open, filename: "checking.csv")
      expect(invoice).not_to be_valid
      expect(invoice.errors[:pdf]).to include("must be a PDF")
    end

    it "rejects files over the size limit" do
      stub_const("Invoice::PDF_MAX_BYTES", 10)
      invoice = build(:invoice)
      invoice.pdf.attach(io: file_fixture("invoice.pdf").open, filename: "invoice.pdf")
      expect(invoice).not_to be_valid
      expect(invoice.errors[:pdf]).to include("must be smaller than 10 MB")
    end
  end

  describe ".receivables_by_business" do
    it "sums outstanding and overdue over sent invoices per business" do
      create(:invoice, business: business, amount_cents: 10_000, due_date: today + 5)
      late = create(:invoice, business: business, amount_cents: 30_000, due_date: today - 1)
      create(:invoice_payment, invoice: late, amount_cents: 5_000)
      create(:invoice, business: business, amount_cents: 99_000, status: "draft")

      totals = Invoice.receivables_by_business([ business.id ], today: today)
      expect(totals).to eq(business.id => { outstanding_cents: 35_000, overdue_cents: 25_000 })
    end
  end

  describe "sales tax" do
    let(:business) { create(:business) }

    before { create(:sales_tax_profile, business: business) }

    it "is part of the amount and must be below it" do
      expect(build(:invoice, business: business, amount_cents: 109_250, sales_tax: "92.50")).to be_valid
      expect(build(:invoice, business: business, amount_cents: 10_000, sales_tax_cents: 10_000)).not_to be_valid
      expect(build(:invoice, business: business, sales_tax: "-1")).not_to be_valid
      expect(build(:invoice, business: business, sales_tax: "").tap(&:valid?).sales_tax_cents).to eq(0)
    end

    it "needs an active sales tax profile" do
      invoice = build(:invoice, sales_tax_cents: 100)
      expect(invoice).not_to be_valid
      expect(invoice.errors[:sales_tax]).to include("needs an active sales tax profile")
    end

    it "can't change once payments are linked" do
      invoice = create(:invoice, business: business, amount_cents: 109_250, sales_tax_cents: 9_250)
      create(:invoice_payment, invoice: invoice, amount_cents: 10_000)
      expect(invoice.reload.update(sales_tax_cents: 0)).to be(false)
      expect(invoice.errors[:base]).to include("Unlink payments before changing sales tax.")
    end
  end
end
