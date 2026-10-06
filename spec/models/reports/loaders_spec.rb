require "rails_helper"

RSpec.describe "Report loaders" do
  let(:business) { create(:business) }
  let(:account) { create(:account, business: business) }
  let(:office) { create(:category, business: business, name: "Office") }
  let(:year) { Date.new(2026, 1, 1)..Date.new(2026, 12, 31) }

  describe Reports::CategoryTotals do
    it "sums countable categorized transactions in an inclusive range" do
      create(:transaction, account: account, category: office, amount_cents: -1_000, posted_on: Date.new(2026, 1, 1))
      create(:transaction, account: account, category: office, amount_cents: -2_000, posted_on: Date.new(2026, 12, 31))
      create(:transaction, account: account, category: office, amount_cents: 500, posted_on: Date.new(2026, 6, 1))
      create(:transaction, account: account, category: office, amount_cents: -9_999, posted_on: Date.new(2027, 1, 1))
      create(:transaction, account: account, category: office, amount_cents: -9_999, excluded: true)
      create(:transaction, account: account, category: office, amount_cents: -9_999).update_columns(transfer: true)
      create(:transaction, account: account, amount_cents: -9_999)
      other = create(:transaction, amount_cents: -9_999)
      other.update!(category: create(:category, business: other.account.business))

      totals = Reports::CategoryTotals.load(business_ids: [business.id], range: year)
      expect(totals.map { [_1.business_id, _1.name, _1.kind, _1.sum_cents] }).to eq([[business.id, "Office", "expense", -2_500]])
    end
  end

  describe Reports::MileageTotals do
    it "values each year at its own rate and reports years without a rate" do
      create(:tax_parameters, year: 2026, standard_mileage_rate_tenth_cents: 725)
      create(:mileage_entry, business: business, driven_on: Date.new(2026, 12, 31), miles_tenths: 617, round_trip: true)
      create(:mileage_entry, business: business, driven_on: Date.new(2027, 1, 1), miles_tenths: 100)

      result = Reports::MileageTotals.load(business_ids: [business.id], range: Date.new(2026, 1, 1)..Date.new(2027, 12, 31))
      expect(result.miles_tenths).to eq(1334)
      expect(result.deduction_cents).to eq(8_947)
      expect(result.missing_rate_years).to eq([2027])
    end
  end
end
