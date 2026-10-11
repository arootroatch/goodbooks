require "rails_helper"

RSpec.describe SalesTax::RemittancePeriod do
  let(:business) { create(:business) }
  let!(:profile) { create(:sales_tax_profile, business: business) }
  let(:account) { create(:account, business: business) }
  let(:sales) { create(:category, :income, business: business, name: "Sales") }
  let(:remittance) { business.categories.sales_tax_remittance.sole }

  def taxed_sale(on) = create(:transaction, account: account, category: sales, amount_cents: 10_925, sales_tax_cents: 925, posted_on: on)

  it "defaults to the oldest ended period with a balance owed" do
    taxed_sale(Date.new(2026, 2, 1))
    taxed_sale(Date.new(2026, 5, 1))
    expect(described_class.default_for(business, Date.new(2026, 7, 10), today: Date.new(2026, 7, 10))).to eq(Date.new(2026, 1, 1))
  end

  it "falls back to the most recent ended period, then the current one" do
    expect(described_class.default_for(business, Date.new(2026, 7, 10), today: Date.new(2026, 7, 10))).to eq(Date.new(2026, 4, 1))
    expect(described_class.default_for(business, Date.new(2026, 2, 10), today: Date.new(2026, 2, 10))).to eq(Date.new(2026, 1, 1))
  end

  it "is nil without a profile" do
    expect(described_class.default_for(create(:business), Date.new(2026, 7, 10))).to be_nil
  end

  describe "on transactions" do
    it "assigns the default when a rule or a person categorizes a remittance, and clears it when it leaves" do
      taxed_sale(Date.new(2026, 2, 1))
      payment = create(:transaction, account: account, payee: "TN DEPT OF REVENUE", amount_cents: -925, posted_on: Date.new(2026, 4, 15))
      create(:rule, business: business, value: "TN DEPT", category: remittance)
      RuleApplier.new(business).apply([ payment ])
      expect(payment.reload.sales_tax_period_starts_on).to eq(Date.new(2026, 1, 1))
      payment.update!(category: create(:category, business: business), rule: nil)
      expect(payment.sales_tax_period_starts_on).to be_nil
    end

    it "keeps a chosen period and rejects one that isn't a period start" do
      payment = create(:transaction, account: account, category: remittance, amount_cents: -925, posted_on: Date.new(2026, 7, 15),
                                     sales_tax_period_starts_on: Date.new(2026, 4, 1))
      expect(payment.sales_tax_period_starts_on).to eq(Date.new(2026, 4, 1))
      expect(payment.update(sales_tax_period_starts_on: Date.new(2026, 4, 2))).to be(false)
      expect(payment.errors[:sales_tax_period_starts_on]).to include("isn't a filing period for this business")
    end
  end
end
