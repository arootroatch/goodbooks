require "rails_helper"

RSpec.describe SalesTaxFiling do
  it "is valid for a period start in the business's calendar" do
    expect(build(:sales_tax_filing)).to be_valid
  end

  it "rejects a date that isn't a period start, a future filing date, and a second filing" do
    filing = create(:sales_tax_filing)
    expect(build(:sales_tax_filing, business: filing.business, period_starts_on: Date.new(2026, 2, 1))).not_to be_valid
    expect(build(:sales_tax_filing, business: filing.business, period_starts_on: Date.new(2026, 4, 1), filed_on: Date.current + 1)).not_to be_valid
    duplicate = build(:sales_tax_filing, business: filing.business)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:period_starts_on]).to include("is already filed")
  end

  it "needs a sales tax profile" do
    filing = build(:sales_tax_filing, business: create(:business))
    expect(filing).not_to be_valid
    expect(filing.errors[:period_starts_on]).to include("isn't a filing period for this business")
  end
end
