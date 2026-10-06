module Invoices
  module NumberSuggester
    FIRST = "1001"

    def self.next(numbers)
      parsed = numbers.filter_map { |number| number.to_s.match(/\A(.*?)(\d+)\z/)&.captures }
      return FIRST if parsed.empty?

      prefix, digits = parsed.max_by { |_, d| d.to_i }
      "#{prefix}#{(digits.to_i + 1).to_s.rjust(digits.length, "0")}"
    end
  end
end
