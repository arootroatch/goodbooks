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

      totals = Reports::CategoryTotals.load(business_ids: [ business.id ], range: year)
      expect(totals.map { [ _1.business_id, _1.name, _1.kind, _1.sum_cents ] }).to eq([ [ business.id, "Office", "expense", -2_500 ] ])
    end

    context "with sales tax and processor fees" do
      let!(:profile) { create(:sales_tax_profile, business: business) }
      let(:sales) { create(:category, :income, business: business, name: "Sales") }
      let!(:fees) { create(:category, business: business, name: "Merchant fees", schedule_c_line: "10", processor_fees: true) }

      before do
        create(:transaction, account: account, category: sales, amount_cents: 97_070, processor_fee_cents: 2_930, sales_tax_cents: 8_241,
                             posted_on: Date.new(2026, 3, 6))
      end

      def totals = Reports::CategoryTotals.load(business_ids: [ business.id ], range: year).to_h { [ _1.name, _1.sum_cents ] }

      it "nets out sales tax and adds the fee back to income, showing the fee as an expense" do
        expect(totals).to eq("Sales" => 91_759, "Merchant fees" => -2_930)
      end

      it "merges fees with real transactions in the fee category" do
        create(:transaction, account: account, category: fees, amount_cents: -1_500, posted_on: Date.new(2026, 3, 7))
        expect(totals["Merchant fees"]).to eq(-4_430)
      end

      it "nets out invoice tax shares" do
        invoice = create(:invoice, business: business, amount_cents: 54_625, sales_tax_cents: 4_625)
        create(:invoice_payment, invoice: invoice, amount_cents: 54_625, sales_tax_cents: 4_625,
                                 deposit: create(:transaction, account: account, category: sales, amount_cents: 54_625, posted_on: Date.new(2026, 3, 8)))
        expect(totals["Sales"]).to eq(91_759 + 50_000)
      end

      it "leaves remittances out of income and expense" do
        remittance = business.categories.sales_tax_remittance.sole
        create(:transaction, account: account, category: remittance, amount_cents: -8_241, posted_on: Date.new(2026, 4, 15))
        expect(totals.keys).to contain_exactly("Sales", "Merchant fees")
      end

      it "agrees on the P&L, Schedule C, and the household P&L" do
        loaded = Reports::CategoryTotals.load(business_ids: [ business.id ], range: year)
        pnl = Reports::ProfitAndLoss.new(category_totals: loaded, mileage_deduction_cents: 0)
        expect(pnl.net_profit_cents).to eq(91_759 - 2_930)
        lines = Reports::ScheduleCSummary.new(category_totals: loaded, mileage_deduction_cents: 0).lines
        expect(lines.slice("1", "10")).to eq("1" => 91_759, "10" => 2_930)
        household = Reports::HouseholdProfitAndLoss.new({ business => pnl })
        expect(household.column(:net_profit_cents)[:total]).to eq(pnl.net_profit_cents)
      end
    end
  end

  describe Reports::MileageTotals do
    it "values each year at its own rate and reports years without a rate" do
      create(:tax_parameters, year: 2026, standard_mileage_rate_tenth_cents: 725)
      create(:mileage_entry, business: business, driven_on: Date.new(2026, 12, 31), miles_tenths: 617, round_trip: true)
      create(:mileage_entry, business: business, driven_on: Date.new(2027, 1, 1), miles_tenths: 100)

      result = Reports::MileageTotals.load(business_ids: [ business.id ], range: Date.new(2026, 1, 1)..Date.new(2027, 12, 31))
      expect(result.miles_tenths).to eq(1334)
      expect(result.deduction_cents).to eq(8_947)
      expect(result.missing_rate_years).to eq([ 2027 ])
    end
  end
end
