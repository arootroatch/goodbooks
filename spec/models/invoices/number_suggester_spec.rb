require "rails_helper"

RSpec.describe Invoices::NumberSuggester do
  it "starts at 1001" do
    expect(described_class.next([])).to eq("1001")
  end

  it "increments the highest number, keeping prefix and zero padding" do
    expect(described_class.next(%w[INV-0009 INV-0042 INV-0010])).to eq("INV-0043")
  end

  it "grows past the padding width" do
    expect(described_class.next(%w[A-9])).to eq("A-10")
    expect(described_class.next(%w[99])).to eq("100")
  end

  it "ignores numbers without trailing digits" do
    expect(described_class.next(%w[DRAFT 2026-007])).to eq("2026-008")
    expect(described_class.next(%w[DRAFT])).to eq("1001")
  end
end
