class CsvImport::Preview
  Entry = Data.define(:row, :status, :proposed_rule)

  attr_reader :entries

  def self.build(csv_import)
    account = csv_import.account
    rows = CsvImport::Parser.new(csv_import.effective_mapping, account_id: account.id).parse(csv_import.content)
    existing = account.transactions.where(external_id: rows.filter_map(&:external_id)).pluck(:external_id).to_set
    rules = account.business.rules.applicable.ordered.includes(:category).to_a

    new(rows.map do |row|
      if !row.valid? then Entry.new(row:, status: :error, proposed_rule: nil)
      elsif existing.include?(row.external_id) then Entry.new(row:, status: :duplicate, proposed_rule: nil)
      else Entry.new(row:, status: :new, proposed_rule: RuleEngine.match(row.rule_attributes, rules))
      end
    end)
  end

  def initialize(entries)
    @entries = entries
  end

  def new_entries = entries.select { _1.status == :new }
  def duplicate_entries = entries.select { _1.status == :duplicate }
  def error_entries = entries.select { _1.status == :error }
end
