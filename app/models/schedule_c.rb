module ScheduleC
  LINES = {
    "1" => "Gross receipts or sales",
    "2" => "Returns and allowances",
    "6" => "Other income",
    "8" => "Advertising",
    "9" => "Car and truck expenses",
    "10" => "Commissions and fees",
    "11" => "Contract labor",
    "13" => "Depreciation",
    "15" => "Insurance (other than health)",
    "16b" => "Interest (other)",
    "17" => "Legal and professional services",
    "18" => "Office expense",
    "20b" => "Rent or lease (other business property)",
    "21" => "Repairs and maintenance",
    "22" => "Supplies",
    "23" => "Taxes and licenses",
    "24a" => "Travel",
    "24b" => "Deductible meals",
    "25" => "Utilities",
    "26" => "Wages",
    "27a" => "Other expenses",
    "30" => "Business use of home"
  }.freeze

  INCOME_LINES = %w[1 2 6].freeze
  COMPUTED_LINES = %w[30].freeze
  EXPENSE_LINES = (LINES.keys - INCOME_LINES - COMPUTED_LINES).freeze

  def self.label(code) = "Line #{code}: #{LINES.fetch(code)}"

  def self.options_for(kind)
    codes = kind.to_s == "income" ? INCOME_LINES : EXPENSE_LINES
    codes.map { |code| [ label(code), code ] }
  end
end
