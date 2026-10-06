require "rails_helper"

RSpec.describe CsvImport::Parser do
  let(:mapping) { CsvImport::Mapping.new(date_column: "Date", payee_column: "Description", memo_column: "Memo", amount_column: "Amount") }
  let(:parser) { described_class.new(mapping, account_id: 7) }

  def parse(content, with: parser) = with.parse(content)

  it "parses rows into normalized attributes" do
    rows = parse(<<~CSV)
      Date,Description,Memo,Amount
      01/05/2026,  ADOBE   CREATIVE ,monthly,-54.99
      01/06/2026,Client payment,,"1,500.00"
    CSV
    expect(rows.map { [_1.line, _1.posted_on, _1.payee, _1.memo, _1.amount_cents] }).to eq([
      [2, Date.new(2026, 1, 5), "ADOBE CREATIVE", "monthly", -5499],
      [3, Date.new(2026, 1, 6), "Client payment", nil, 150000]
    ])
    expect(rows).to all(be_valid)
  end

  it "handles a BOM, CRLF line endings, and blank lines" do
    content = "\uFEFFDate,Description,Memo,Amount\r\n01/05/2026,Coffee,,-4.50\r\n\r\n,,,\r\n"
    expect(content).to start_with("\uFEFF")
    rows = parse(content)
    expect(rows.size).to eq(1)
    expect(rows.first.amount_cents).to eq(-450)
  end

  it "gives identical rows in one file distinct, repeatable ids" do
    content = <<~CSV
      Date,Description,Memo,Amount
      01/06/2026,Client payment,,100.00
      01/06/2026,Client payment,,100.00
    CSV
    first, second = parse(content)
    expect(first.external_id).not_to eq(second.external_id)
    expect(parse(content).map(&:external_id)).to eq([first.external_id, second.external_id])
  end

  it "gives the same id to the same row in an overlapping file" do
    jan = parse("Date,Description,Memo,Amount\n01/05/2026,Coffee,,-4.50\n01/07/2026,Tea,,-3.00\n")
    overlap = parse("Date,Description,Memo,Amount\n01/07/2026,Tea,,-3.00\n01/09/2026,Cake,,-6.00\n")
    expect(overlap.first.external_id).to eq(jan.last.external_id)
  end

  it "scopes ids to the account" do
    other = described_class.new(mapping, account_id: 8)
    content = "Date,Description,Memo,Amount\n01/05/2026,Coffee,,-4.50\n"
    expect(parse(content).first.external_id).not_to eq(parse(content, with: other).first.external_id)
  end

  it "supports debit and credit columns" do
    split = CsvImport::Mapping.new(date_column: "Date", payee_column: "Payee", debit_column: "Debit", credit_column: "Credit")
    rows = described_class.new(split, account_id: 1).parse("Date,Payee,Debit,Credit\n01/05/2026,Store,12.00,\n01/06/2026,Client,,500\n")
    expect(rows.map(&:amount_cents)).to eq([-1200, 50000])
  end

  context "with debit and credit columns" do
    let(:split) { CsvImport::Mapping.new(date_column: "Date", payee_column: "Payee", debit_column: "Debit", credit_column: "Credit") }

    def split_row(debit, credit)
      described_class.new(split, account_id: 1).parse("Date,Payee,Debit,Credit\n01/05/2026,Store,#{debit},#{credit}\n").first
    end

    it "reads the credit when the debit is 0.00" do
      expect(split_row("0.00", "500.00").amount_cents).to eq(50000)
    end

    it "reads the credit when the debit is 0" do
      expect(split_row("0", "500").amount_cents).to eq(50000)
    end

    it "reads the debit when the credit is 0.00" do
      expect(split_row("12.00", "0.00").amount_cents).to eq(-1200)
    end

    it "flags rows with both a debit and a credit as ambiguous" do
      row = split_row("5.00", "7.00")
      expect(row.error).to eq("Amount is ambiguous (both debit and credit)")
    end

    it "flags rows with neither as blank" do
      expect(split_row("0.00", "0.00").error).to eq("Amount can't be blank")
      expect(split_row("", "").error).to eq("Amount can't be blank")
    end

    it "applies invert_sign afterwards" do
      split.invert_sign = true
      expect(split_row("12.00", "").amount_cents).to eq(1200)
    end
  end

  it "inverts signs for card statements" do
    mapping.invert_sign = true
    expect(parse("Date,Description,Memo,Amount\n01/05/2026,Store,,12.00\n").first.amount_cents).to eq(-1200)
  end

  it "skips preamble rows" do
    mapping.skip_rows = 2
    rows = parse("Bank of Example\nAccount 1234\nDate,Description,Memo,Amount\n01/05/2026,Store,,-1\n")
    expect(rows.first.line).to eq(4)
    expect(rows.first.payee).to eq("Store")
  end

  it "uses the chosen date format" do
    mapping.date_format = "YYYY-MM-DD"
    expect(parse("Date,Description,Memo,Amount\n2026-01-05,Store,,-1\n").first.posted_on).to eq(Date.new(2026, 1, 5))
  end

  it "reports bad rows with their line numbers instead of dropping them" do
    rows = parse(<<~CSV)
      Date,Description,Memo,Amount
      13/45/2026,Bad date,,-1
      01/05/2026,Bad amount,,abc
      01/05/2026,,,-1
      01/05/2026,Fine,,-1
    CSV
    expect(rows.map { [_1.line, _1.error] }).to eq([
      [2, "Invalid date"], [3, "Amount is not a valid amount"], [4, "Missing payee"], [5, nil]
    ])
    expect(rows.first.external_id).to be_nil
  end

  it "raises FileError for non-UTF-8 content" do
    expect { parse("Date,Description\n\xFF\xFE".b) }.to raise_error(CsvImport::Parser::FileError, "File must be UTF-8 encoded.")
  end

  it "raises FileError when a mapped column is missing" do
    expect { parse("Date,Payee,Amount\n01/05/2026,Store,-1\n") }.to raise_error(CsvImport::Parser::FileError, "Column not found: Description, Memo")
  end

  it "raises FileError for an empty file" do
    expect { parse("") }.to raise_error(CsvImport::Parser::FileError, "File has no header row.")
  end

  it "reads headers after skipped rows" do
    expect(described_class.headers("junk\n Date , Amount\n1,2\n", skip_rows: 1)).to eq(["Date", "Amount"])
  end

  it "exposes rule attributes" do
    row = parse("Date,Description,Memo,Amount\n01/05/2026,Store,x,-1\n").first
    expect(row.rule_attributes).to eq(payee: "Store", memo: "x", amount_cents: -100)
  end

  it "rejects two-digit years under a four-digit format" do
    row = parse("Date,Description,Memo,Amount\n1/5/26,Store,,-1\n").first
    expect(row.error).to eq("Invalid date")
    expect(row.external_id).to be_nil
  end

  it "parses two-digit years under MM/DD/YY" do
    mapping.date_format = "MM/DD/YY"
    expect(parse("Date,Description,Memo,Amount\n01/05/26,Store,,-1\n").first.posted_on).to eq(Date.new(2026, 1, 5))
  end

  it "raises FileError when a mapped column appears more than once" do
    amount = CsvImport::Mapping.new(date_column: "Date", payee_column: "Description", amount_column: "Amount")
    expect { described_class.new(amount, account_id: 1).parse("Date,Description,Amount,Amount\n01/05/2026,Store,1,2\n") }
      .to raise_error(CsvImport::Parser::FileError, "Column appears more than once: Amount")
  end

  it "matches mapped column names ignoring surrounding whitespace" do
    padded = CsvImport::Mapping.new(date_column: "Date ", payee_column: " Description", amount_column: "Amount ")
    rows = described_class.new(padded, account_id: 1).parse("Date,Description,Amount\n01/05/2026,Store,-1\n")
    expect(rows.first).to be_valid
  end
end
