require "rails_helper"

RSpec.describe InvoicePayments do
  let(:business) { create(:business) }
  let(:account) { create(:account, business: business) }
  let!(:sales) { create(:category, :income, business: business, name: "Sales") }
  let(:invoice) { create(:invoice, business: business, amount_cents: 120_000) }
  let(:deposit) { create(:transaction, account: account, amount_cents: 120_000, posted_on: Date.new(2026, 2, 3), payee: "ACME") }

  describe ".link" do
    it "pays an exact match, categorizes the deposit as Sales by the user, and marks the invoice paid" do
      result = described_class.link(invoice: invoice, deposit: deposit)
      expect(result).to be_ok
      expect(result.payment.amount_cents).to eq(120_000)
      expect(deposit.reload.category).to eq(sales)
      expect(deposit.categorized_by).to eq("user")
      expect(invoice.reload).to be_paid
      expect(invoice.paid_on).to eq(Date.new(2026, 2, 3))
    end

    it "records a partial payment and leaves the invoice sent" do
      result = described_class.link(invoice: invoice, deposit: deposit, amount_cents: 20_000)
      expect(result.payment.amount_cents).to eq(20_000)
      expect(invoice.reload).to be_sent
      expect(invoice.outstanding_cents).to eq(100_000)
    end

    it "keeps an existing income category" do
      other = create(:category, :income, business: business, name: "Other income", schedule_c_line: "6")
      deposit.update!(category: other)
      described_class.link(invoice: invoice, deposit: deposit)
      expect(deposit.reload.category).to eq(other)
    end

    it "asks for a category when the business has several gross-receipts categories" do
      create(:category, :income, business: business, name: "Retail sales")
      result = described_class.link(invoice: invoice, deposit: deposit)
      expect(result.error).to eq("Choose an income category for this deposit.")
      chosen = described_class.link(invoice: invoice, deposit: deposit, category: sales)
      expect(chosen).to be_ok
    end

    it "ignores a category from another business" do
      result = described_class.link(invoice: invoice, deposit: deposit, category: create(:category, :income))
      expect(result.error).to eq("Choose an income category for this deposit.")
    end

    {
      "a draft invoice" => [ -> { invoice.update!(status: "draft") }, "Only sent invoices can take payments." ],
      "a void invoice" => [ -> { invoice.update!(status: "void") }, "Only sent invoices can take payments." ],
      "a paid invoice" => [ -> { invoice.update!(status: "paid") }, "This invoice is already fully paid." ],
      "money out" => [ -> { deposit.update!(amount_cents: -120_000) }, "Only deposits (money in) can pay an invoice." ],
      "a transfer" => [ -> { deposit.update!(transfer: true) }, "Transfers can't pay an invoice." ],
      "an excluded row" => [ -> { deposit.update!(excluded: true) }, "Excluded transactions can't pay an invoice." ],
      "an expense" => [ -> { deposit.update!(category: create(:category, business: business)) }, "Only deposits in an income category can pay an invoice." ]
    }.each do |label, (setup, message)|
      it "rejects #{label}" do
        instance_exec(&setup)
        result = described_class.link(invoice: invoice, deposit: deposit)
        expect(result.error).to eq(message)
        expect(InvoicePayment.count).to eq(0)
      end
    end

    it "rejects a deposit from another business" do
      foreign = create(:transaction, amount_cents: 120_000)
      expect(described_class.link(invoice: invoice, deposit: foreign).error).to eq("That deposit belongs to another business.")
    end

    it "rejects linking the same deposit twice (double submit)" do
      described_class.link(invoice: invoice, deposit: deposit, amount_cents: 10_000)
      expect(described_class.link(invoice: invoice, deposit: deposit).error).to eq("That deposit is already linked to this invoice.")
    end

    it "rejects over-allocation and reports allocation errors" do
      result = described_class.link(invoice: invoice, deposit: deposit, amount_cents: 120_001)
      expect(result.error).to eq("Amount can't exceed the invoice's outstanding $1,200.00.")
    end

    it "re-reads allocations under the lock (stale deposit from an earlier page load)" do
      stale = Transaction.find(deposit.id)
      stale.invoice_payments.load
      other = create(:invoice, business: business, amount_cents: 120_000)
      described_class.link(invoice: other, deposit: Transaction.find(deposit.id))

      expect(invoice).to receive(:lock!).and_call_original
      result = described_class.link(invoice: invoice, deposit: stale)
      expect(result.error).to eq("This deposit is already fully allocated.")
      expect(InvoicePayment.where(deposit_id: deposit.id).sum(:amount_cents)).to eq(120_000)
    end
  end

  describe ".unlink" do
    it "removes the payment and reverts a paid invoice to sent, keeping the deposit's category" do
      payment = described_class.link(invoice: invoice, deposit: deposit).payment
      expect(payment.invoice).to receive(:lock!).and_call_original
      expect(payment.deposit).to receive(:lock!).and_call_original
      result = described_class.unlink(payment)
      expect(result).to be_ok
      expect(InvoicePayment.exists?(payment.id)).to be(false)
      expect(invoice.reload).to be_sent
      expect(invoice.paid_on).to be_nil
      expect(deposit.reload.category).to eq(sales)
    end

    context "with a processor fee" do
      let(:payout) { create(:transaction, account: account, amount_cents: 116_490, payee: "STRIPE", posted_on: Date.new(2026, 2, 3)) }

      it "records the fee and pays the invoice in full from the payout's gross" do
        result = described_class.link(invoice: invoice, deposit: payout, processor_fee_cents: 3_510)
        expect(result).to be_ok
        expect(result.payment.amount_cents).to eq(120_000)
        expect(payout.reload.processor_fee_cents).to eq(3_510)
        expect(invoice.reload).to be_paid
      end

      it "keeps a fee the deposit already has" do
        payout.update!(processor_fee_cents: 3_510)
        described_class.link(invoice: invoice, deposit: payout, processor_fee_cents: 99)
        expect(payout.reload.processor_fee_cents).to eq(3_510)
        expect(invoice.reload).to be_paid
      end
    end
  end

  it "lists gross-receipts categories" do
    create(:category, :income, business: business, name: "Archived", archived_at: Time.current)
    create(:category, :income, business: business, name: "Other income", schedule_c_line: "6")
    expect(described_class.gross_receipts_categories(business)).to eq([ sales ])
  end
end
