require "rails_helper"

RSpec.describe "Report CSVs" do
  let(:business) { create(:business, name: "Pat Consulting") }
  let(:account) { create(:account, business: business, name: "Checking") }
  let(:meals) { create(:category, business: business, name: "Meals", schedule_c_line: "24b", deductible_bps: 5000) }

  describe Reports::CsvSafe do
    it "neutralizes formula-looking text" do
      expect(Reports::CsvSafe.text("=HYPERLINK(1)")).to eq("'=HYPERLINK(1)")
      expect(Reports::CsvSafe.text("@SUM")).to eq("'@SUM")
      expect(Reports::CsvSafe.text("Coffee")).to eq("Coffee")
      expect(Reports::CsvSafe.text(nil)).to be_nil
    end

    it "prefixes every dangerous leading form" do
      ["+1", "-2", "\t=x", "\r=x", "\n=x", "  =SUM(A1)", "|cmd", "%x", "＝1"].each do |text|
        expect(Reports::CsvSafe.text(text)).to eq("'#{text}")
      end
    end

    it "neutralizes NBSP and ideographic space before dangerous characters" do
      expect(Reports::CsvSafe.text(" =x")).to eq("' =x")
      expect(Reports::CsvSafe.text("　=x")).to eq("'　=x")
    end

    it "leaves ordinary text alone" do
      expect(Reports::CsvSafe.text("Office Depot")).to eq("Office Depot")
      expect(Reports::CsvSafe.text("Client - ACME")).to eq("Client - ACME")
    end
  end

  describe Reports::TransactionCsv do
    it "writes one row per transaction with deductible amounts" do
      create(:transaction, account: account, category: meals, payee: "=cmd", amount_cents: -3_333, posted_on: Date.new(2026, 2, 1))
      rows = CSV.parse(Reports::TransactionCsv.generate(Transaction.includes(:category, account: :business)))
      expect(rows.first).to eq(Reports::TransactionCsv::HEADERS)
      expect(rows.second).to eq(["2026-02-01", "Pat Consulting", "Checking", "'=cmd", nil, "-33.33", "Meals", "24b", "no", "16.67"])
    end
  end

  describe Reports::MileageLogCsv do
    it "writes entries, a total, and the deduction" do
      entry = create(:mileage_entry, business: business, miles_tenths: 1234, driven_on: Date.new(2026, 3, 2))
      rows = CSV.parse(Reports::MileageLogCsv.generate([entry], rate_tenth_cents: 725, year: 2026))
      expect(rows[1]).to eq(["2026-03-02", "Client meeting", "Home office", "Client", "123.4", "no"])
      expect(rows[-2]).to eq(["Total", nil, nil, nil, "123.4", nil])
      expect(rows[-1]).to eq(["Deduction at 72.5¢/mile", nil, nil, nil, "89.47", nil])
    end

    it "notes the missing rate instead of a deduction" do
      rows = CSV.parse(Reports::MileageLogCsv.generate([], rate_tenth_cents: nil, year: 2026))
      expect(rows.last).to eq(["Deduction: no IRS rate set for 2026", nil, nil, nil, nil, nil])
    end
  end
end
