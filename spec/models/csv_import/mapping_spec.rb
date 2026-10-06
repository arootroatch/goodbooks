require "rails_helper"

RSpec.describe CsvImport::Mapping do
  let(:base) { { date_column: "Date", payee_column: "Description" } }

  it "is valid with a single amount column" do
    expect(described_class.new(base.merge(amount_column: "Amount"))).to be_valid
  end

  it "is valid with debit and credit columns" do
    expect(described_class.new(base.merge(debit_column: "Debit", credit_column: "Credit"))).to be_valid
  end

  it "rejects both styles, neither style, or half a split" do
    expect(described_class.new(base.merge(amount_column: "A", debit_column: "D", credit_column: "C"))).not_to be_valid
    expect(described_class.new(base)).not_to be_valid
    expect(described_class.new(base.merge(debit_column: "D"))).not_to be_valid
  end

  it "rejects an unknown date format and negative skip rows" do
    expect(described_class.new(base.merge(amount_column: "A", date_format: "%d.%m"))).not_to be_valid
    expect(described_class.new(base.merge(amount_column: "A", skip_rows: -1))).not_to be_valid
  end

  it "round-trips through a hash" do
    mapping = described_class.new(base.merge(amount_column: "Amount", invert_sign: true))
    again = described_class.new(mapping.to_h)
    expect(again.to_h).to eq(mapping.to_h)
    expect(again.invert_sign).to be(true)
  end
end
