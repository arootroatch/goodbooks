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

  describe "invoice sales tax" do
    let!(:profile) { create(:sales_tax_profile, business: business) }
    let!(:consulting) { create(:category, :income, business: business, name: "Consulting", sales_tax_treatment: "exempt") }
    let(:taxed) { create(:invoice, business: business, amount_cents: 109_250, sales_tax_cents: 9_250) }

    it "stores the payment's share and leaves the deposit's direct tax alone" do
      check = create(:transaction, account: account, amount_cents: 109_250, payee: "RIVERSIDE CHECK")
      result = described_class.link(invoice: taxed, deposit: check)
      expect(result.payment.sales_tax_cents).to eq(9_250)
      expect(check.reload.sales_tax_cents).to eq(0)
      expect(check.total_sales_tax_cents).to eq(9_250)
      expect(check.category).to eq(sales)
    end

    it "keeps a batched payout's direct tax and invoice share apart, and unlink removes only the share" do
      invoice = create(:invoice, business: business, amount_cents: 54_625, sales_tax_cents: 4_625)
      payout = create(:transaction, account: account, amount_cents: 82_000, processor_fee_cents: 2_625, payee: "STRIPE",
                                    category: sales, sales_tax_cents: 2_540)
      result = described_class.link(invoice: invoice, deposit: payout, amount_cents: 54_625)
      expect(result.payment.sales_tax_cents).to eq(4_625)
      expect(payout.reload.total_sales_tax_cents).to eq(7_165)
      described_class.unlink(result.payment)
      expect(payout.reload.total_sales_tax_cents).to eq(2_540)
      expect(payout.sales_tax_cents).to eq(2_540)
    end

    it "makes the final partial payment's share absorb rounding" do
      first = create(:transaction, account: account, amount_cents: 33_333, payee: "PART ONE")
      second = create(:transaction, account: account, amount_cents: 75_917, payee: "PART TWO")
      one = described_class.link(invoice: taxed, deposit: first).payment
      two = described_class.link(invoice: taxed, deposit: second).payment
      expect(one.sales_tax_cents).to eq(2_822)
      expect(one.sales_tax_cents + two.sales_tax_cents).to eq(9_250)
    end

    it "rejects an exempt deposit for a taxed invoice" do
      deposit.update!(category: consulting)
      result = described_class.link(invoice: taxed, deposit: deposit)
      expect(result.error).to eq("This invoice includes sales tax — categorize the deposit as a taxable sale.")
      requested = create(:transaction, account: account, amount_cents: 109_250)
      expect(described_class.link(invoice: taxed, deposit: requested, category: consulting).error)
        .to eq("This invoice includes sales tax — categorize the deposit as a taxable sale.")
    end

    it "picks the single taxable gross-receipts category even when an exempt one is also on line 1" do
      check = create(:transaction, account: account, amount_cents: 109_250)
      expect(described_class.link(invoice: taxed, deposit: check)).to be_ok
      expect(check.reload.category).to eq(sales)
    end

    it "refuses a share that would push the deposit's tax to its gross" do
      invoice = create(:invoice, business: business, amount_cents: 10_000, sales_tax_cents: 9_000)
      payout = create(:transaction, account: account, amount_cents: 10_000, category: sales, sales_tax_cents: 1_500)
      result = described_class.link(invoice: invoice, deposit: payout)
      expect(result.error).to eq("Sales tax on this deposit would reach its gross amount — lower its direct sales tax first.")
      expect(InvoicePayment.count).to eq(0)
    end

    it "doesn't keep a processor fee when the payment amount is refused" do
      result = described_class.link(invoice: taxed, deposit: deposit, amount_cents: 200_000, processor_fee_cents: 500)
      expect(result).not_to be_ok
      expect(deposit.reload.processor_fee_cents).to eq(0)
    end
  end
end
