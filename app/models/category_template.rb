module CategoryTemplate
  CATEGORIES = [
    { name: "Sales", kind: "income", schedule_c_line: "1" },
    { name: "Refunds given", kind: "income", schedule_c_line: "2" },
    { name: "Other income", kind: "income", schedule_c_line: "6" },
    { name: "Advertising", kind: "expense", schedule_c_line: "8" },
    { name: "Parking and tolls", kind: "expense", schedule_c_line: "9" },
    { name: "Commissions and fees", kind: "expense", schedule_c_line: "10" },
    { name: "Contract labor", kind: "expense", schedule_c_line: "11" },
    { name: "Insurance", kind: "expense", schedule_c_line: "15" },
    { name: "Legal and professional", kind: "expense", schedule_c_line: "17" },
    { name: "Office expense", kind: "expense", schedule_c_line: "18" },
    { name: "Rent", kind: "expense", schedule_c_line: "20b" },
    { name: "Repairs", kind: "expense", schedule_c_line: "21" },
    { name: "Supplies", kind: "expense", schedule_c_line: "22" },
    { name: "Taxes and licenses", kind: "expense", schedule_c_line: "23" },
    { name: "Travel", kind: "expense", schedule_c_line: "24a" },
    { name: "Meals", kind: "expense", schedule_c_line: "24b", deductible_bps: 5000 },
    { name: "Utilities", kind: "expense", schedule_c_line: "25" },
    { name: "Wages", kind: "expense", schedule_c_line: "26" },
    { name: "Software", kind: "expense", schedule_c_line: "27a" },
    { name: "Phone and internet", kind: "expense", schedule_c_line: "27a" },
    { name: "Bank fees", kind: "expense", schedule_c_line: "27a" },
    { name: "Education", kind: "expense", schedule_c_line: "27a" }
  ].freeze

  def self.apply_to(business)
    CATEGORIES.each { |attrs| business.categories.create!(attrs) }
  end
end
