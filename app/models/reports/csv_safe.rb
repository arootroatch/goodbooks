module Reports
  module CsvSafe
    DANGEROUS = /\A[=+\-@\t\r]/

    def self.text(value)
      return value if value.nil?

      value.to_s.match?(DANGEROUS) ? "'#{value}" : value.to_s
    end
  end
end
