require "rails_helper"

RSpec.describe InvoiceFilter do
  let(:business) { create(:business) }
  let(:today) { Date.new(2026, 10, 6) }
  let(:acme) { create(:client, business: business, name: "Acme") }
  let!(:current) { create(:invoice, business: business, client: acme, number: "C", issue_date: today - 5, due_date: today, amount_cents: 10_000) }
  let!(:late) { create(:invoice, business: business, number: "L", issue_date: today - 40, due_date: today - 10, amount_cents: 20_000) }
  let!(:paid) { create(:invoice, business: business, number: "P", status: "paid", issue_date: today - 60, due_date: today - 30) }
  let!(:draft) { create(:invoice, business: business, number: "D", status: "draft", issue_date: today - 1, due_date: today + 29) }

  def numbers(params) = described_class.new(business.invoices, params, today: today).results.map(&:number)

  it "filters by status" do
    expect(numbers({})).to eq(%w[D C L P])
    expect(numbers(status: "open")).to contain_exactly("C", "L")
    expect(numbers(status: "overdue")).to eq(%w[L])
    expect(numbers(status: "paid")).to eq(%w[P])
    expect(numbers(status: "draft")).to eq(%w[D])
    expect(numbers(status: "nonsense")).to eq(%w[D C L P])
  end

  it "filters by client and issue date" do
    expect(numbers(client_id: acme.id.to_s)).to eq(%w[C])
    expect(numbers(from: (today - 45).iso8601, to: (today - 2).iso8601)).to eq(%w[C L])
  end

  it "totals outstanding and overdue over sent invoices" do
    filter = described_class.new(business.invoices, {}, today: today)
    expect(filter.outstanding_cents).to eq(30_000)
    expect(filter.overdue_cents).to eq(20_000)
  end
end
