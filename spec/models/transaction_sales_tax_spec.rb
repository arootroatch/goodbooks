require "rails_helper"

RSpec.describe Transaction, "sales tax and processor fees" do
  let(:business) { create(:business) }
  let!(:profile) { create(:sales_tax_profile, business: business) }
  let(:account) { create(:account, business: business) }
  let(:sales) { create(:category, :income, business: business, name: "Sales") }
  let(:consulting) { create(:category, :income, business: business, name: "Consulting", sales_tax_treatment: "exempt") }
  let(:payout) { create(:transaction, account: account, amount_cents: 97_070, payee: "STRIPE", category: sales) }

  it "derives gross, total tax, and net income" do
    payout.update!(processor_fee_cents: 2_930, sales_tax_cents: 8_467)
    expect(payout.gross_cents).to eq(100_000)
    expect(payout.total_sales_tax_cents).to eq(8_467)
    expect(payout.net_income_cents).to eq(91_533)
  end

  it "saves blank fee and tax inputs as zero and rejects bad ones" do
    expect(payout.update(processor_fee: "", sales_tax: "")).to be(true)
    expect([ payout.processor_fee_cents, payout.sales_tax_cents ]).to eq([ 0, 0 ])
    expect(payout.update(processor_fee: "abc")).to be(false)
    expect(payout.errors[:processor_fee]).to include("is not a valid amount")
    expect(payout.reload.update(processor_fee: "-5")).to be(false)
    expect(payout.errors[:processor_fee]).to include("can't be negative")
    expect(payout.reload.update(sales_tax: "-5")).to be(false)
    expect(payout.errors[:sales_tax]).to include("can't be negative")
  end

  describe "processor fee" do
    it "is allowed on uncategorized and income deposits" do
      expect(create(:transaction, account: account, amount_cents: 5_000, processor_fee_cents: 175)).to be_persisted
      expect(payout.update(processor_fee_cents: 2_930)).to be(true)
    end

    it "only applies to money in" do
      txn = build(:transaction, account: account, amount_cents: -5_000, processor_fee_cents: 100)
      expect(txn).not_to be_valid
      expect(txn.errors[:processor_fee]).to include("only applies to money in")
    end

    it "isn't used on the personal book" do
      book = create(:business, :personal)
      txn = build(:transaction, account: create(:account, business: book), amount_cents: 5_000, processor_fee_cents: 100)
      expect(txn).not_to be_valid
      expect(txn.errors[:processor_fee]).to include("isn't used on the personal book")
    end

    it "must be cleared before the deposit becomes a transfer, excluded, or an expense" do
      payout.update!(processor_fee_cents: 2_930)
      [ { transfer: true }, { excluded: true }, { category: create(:category, business: business) } ].each do |attrs|
        expect(payout.reload.update(attrs)).to be(false), "accepted #{attrs.keys.first}"
        expect(payout.errors[:base]).to include("Clear the processor fee first.")
      end
    end
  end

  describe "direct sales tax" do
    it "is allowed on a taxable deposit and must stay below gross" do
      expect(payout.update(sales_tax_cents: 8_467)).to be(true)
      expect(payout.update(sales_tax_cents: 97_070)).to be(false)
      expect(payout.errors[:sales_tax]).to include("must be less than the gross amount $970.70")
    end

    it "needs an active sales tax profile" do
      profile.update!(active: false)
      expect(payout.update(sales_tax_cents: 100)).to be(false)
      expect(payout.errors[:sales_tax]).to include("needs an active sales tax profile")
    end

    it "is kept when the profile is later deactivated" do
      payout.update!(sales_tax_cents: 100)
      profile.update!(active: false)
      expect(payout.reload.update(memo: "kept")).to be(true)
    end

    it "only applies to money in, in a taxable category" do
      out = build(:transaction, account: account, amount_cents: -5_000, sales_tax_cents: 100)
      expect(out).not_to be_valid
      expect(out.errors[:sales_tax]).to include("only applies to money in")
      exempt = build(:transaction, account: account, amount_cents: 5_000, category: consulting, sales_tax_cents: 100)
      expect(exempt).not_to be_valid
      expect(exempt.errors[:base]).to include("Clear the sales tax first.")
      uncategorized = build(:transaction, account: account, amount_cents: 5_000, sales_tax_cents: 100)
      expect(uncategorized).not_to be_valid
    end

    it "must be cleared before the deposit becomes a transfer, excluded, or non-taxable" do
      payout.update!(sales_tax_cents: 8_467)
      [ { transfer: true }, { excluded: true }, { category: consulting }, { category: nil } ].each do |attrs|
        expect(payout.reload.update(attrs)).to be(false), "accepted #{attrs.inspect}"
        expect(payout.errors[:base]).to include("Clear the sales tax first.")
      end
    end

    it "counts invoice tax shares toward the total and the guards" do
      invoice = create(:invoice, business: business, amount_cents: 97_070)
      create(:invoice_payment, invoice: invoice, deposit: payout, amount_cents: 97_070, sales_tax_cents: 8_000)
      expect(payout.reload.total_sales_tax_cents).to eq(8_000)
      expect(payout.update(category: consulting)).to be(false)
      expect(payout.errors[:base]).to include("Clear the sales tax first.")
    end
  end

  describe "category guards" do
    it "keeps a taxable category taxable while its deposits carry tax" do
      payout.update!(sales_tax_cents: 100)
      expect(sales.update(sales_tax_treatment: "exempt")).to be(false)
      expect(sales.errors[:sales_tax_treatment]).to include("can't change while deposits in this category carry sales tax")
      payout.update!(sales_tax_cents: 0)
      expect(sales.update(sales_tax_treatment: "exempt")).to be(true)
    end

    it "keeps an income category income while its deposits carry fees" do
      payout.update!(processor_fee_cents: 2_930)
      expect(consulting.update(kind: "expense", schedule_c_line: "18")).to be(true)
      expect(sales.update(kind: "expense", schedule_c_line: "18")).to be(false)
      expect(sales.errors[:kind]).to include("can't change while deposits in this category carry processor fees")
    end
  end
end
