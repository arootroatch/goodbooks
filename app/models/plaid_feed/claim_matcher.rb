module PlaidFeed
  # Pairs incoming rows with existing rows from the other source: same amount, at most WINDOW days apart,
  # nearest date first, then lowest candidate key; each side is used at most once.
  module ClaimMatcher
    WINDOW = 3

    Item = Data.define(:key, :posted_on, :amount_cents)

    def self.call(incoming:, candidates:)
      by_amount = candidates.group_by(&:amount_cents)
      pairs = incoming.each_with_index.flat_map do |row, index|
        by_amount.fetch(row.amount_cents, []).filter_map do |candidate|
          days = (row.posted_on - candidate.posted_on).to_i.abs
          [ days, candidate.key, index, row.key ] if days <= WINDOW
        end
      end

      used = Set.new
      pairs.sort.each_with_object({}) do |(_, candidate_key, _, row_key), result|
        next if result.key?(row_key) || used.include?(candidate_key)

        used << candidate_key
        result[row_key] = candidate_key
      end
    end
  end
end
