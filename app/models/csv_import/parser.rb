require "csv"

class CsvImport::Parser
  DATE_FORMATS = {
    "MM/DD/YYYY" => "%m/%d/%Y",
    "YYYY-MM-DD" => "%Y-%m-%d",
    "MM/DD/YY" => "%m/%d/%y",
    "DD/MM/YYYY" => "%d/%m/%Y"
  }.freeze

  class FileError < StandardError; end

  Row = Data.define(:line, :posted_on, :amount_cents, :payee, :memo, :external_id, :error) do
    def valid? = error.nil?
    def rule_attributes = { payee: payee, memo: memo, amount_cents: amount_cents }
  end

  # Returns [text, transcoded?]; files that aren't valid UTF-8 are read as Windows-1252.
  def self.decode(content)
    text = content.to_s.dup.force_encoding(Encoding::UTF_8)
    return [text, false] if text.valid_encoding?

    [content.to_s.dup.force_encoding("Windows-1252").encode(Encoding::UTF_8), true]
  rescue EncodingError
    raise FileError, "File must be UTF-8 or Windows-1252 encoded."
  end

  def self.table(content, skip_rows: 0)
    text, = decode(content)
    CSV.parse(text.delete_prefix("\uFEFF"), liberal_parsing: true).drop(skip_rows)
  rescue CSV::MalformedCSVError => e
    raise FileError, "Could not read CSV: #{e.message}"
  end

  def self.headers(content, skip_rows: 0)
    table(content, skip_rows: skip_rows).first.to_a.map { _1.to_s.strip }
  end

  def initialize(mapping, account_id:)
    @mapping = mapping
    @account_id = account_id
  end

  def parse(content)
    header, *data = self.class.table(content, skip_rows: @mapping.skip_rows.to_i)
    raise FileError, "File has no header row." if header.nil?

    @columns = header.map { _1.to_s.strip }
    missing = @mapping.columns - @columns
    raise FileError, "Column not found: #{missing.join(", ")}" if missing.any?

    duplicated = @mapping.columns.uniq.select { |name| @columns.count(name) > 1 }
    raise FileError, "Column appears more than once: #{duplicated.join(", ")}" if duplicated.any?

    occurrences = Hash.new(0)
    data.each_with_index.filter_map do |cells, index|
      next if cells.all? { _1.to_s.strip.empty? }

      build_row(cells, @mapping.skip_rows.to_i + index + 2, occurrences)
    end
  end

  private

  def build_row(cells, line, occurrences)
    payee = cell(cells, @mapping.payee_column).squish
    memo = cell(cells, @mapping.memo_column).squish.presence
    failure = ->(message) { Row.new(line:, posted_on: nil, amount_cents: nil, payee:, memo:, external_id: nil, error: message) }

    posted_on = parse_date(cell(cells, @mapping.date_column))
    return failure.("Invalid date") unless posted_on

    amount_cents = begin
      parse_amount(cells)
    rescue Money::ParseError => e
      return failure.("Amount #{e.message}")
    end
    return failure.("Missing payee") if payee.empty?

    key = [posted_on, amount_cents, payee.downcase]
    occurrence = occurrences[key]
    occurrences[key] += 1
    Row.new(line:, posted_on:, amount_cents:, payee:, memo:, external_id: external_id(key, occurrence), error: nil)
  end

  def cell(cells, column)
    return "" if column.blank?

    cells[@columns.index(column)].to_s.strip
  end

  def parse_date(value)
    date = Date.strptime(value, DATE_FORMATS.fetch(@mapping.date_format))
    date if date.year >= 1900
  rescue Date::Error
    nil
  end

  def parse_amount(cells)
    cents =
      if @mapping.amount_column.present?
        Money.parse(cell(cells, @mapping.amount_column)).cents
      else
        split_amount(cells)
      end
    @mapping.invert_sign ? -cents : cents
  end

  def split_amount(cells)
    debit = side_cents(cell(cells, @mapping.debit_column))
    credit = side_cents(cell(cells, @mapping.credit_column))
    raise Money::ParseError, "is ambiguous (both debit and credit)" if debit && credit
    raise Money::ParseError, "can't be blank" unless debit || credit

    debit ? -debit.abs : credit.abs
  end

  # A blank or zero cell counts as absent.
  def side_cents(value)
    return nil if value.blank?

    cents = Money.parse(value).cents
    cents.zero? ? nil : cents
  end

  def external_id(key, occurrence)
    posted_on, amount_cents, payee = key
    Digest::SHA256.hexdigest([@account_id, posted_on.iso8601, amount_cents, payee, occurrence].join("|"))
  end
end
