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

    # The same pairing for ActiveRecord candidates. rows: incoming items responding to posted_on and amount_cents;
    # relation: candidate records (already filtered by the caller), narrowed here to the dates that can match;
    # key: the row attribute that identifies an incoming item. Returns { incoming key => claimed record }.
    def self.pair_records(rows, relation, key:)
      return {} if rows.empty?

      dates = rows.map(&:posted_on)
      candidates = relation.where(posted_on: (dates.min - WINDOW)..(dates.max + WINDOW)).to_a
      pairs = call(
        incoming: rows.map { Item.new(key: _1.public_send(key), posted_on: _1.posted_on, amount_cents: _1.amount_cents) },
        candidates: candidates.map { Item.new(key: _1.id, posted_on: _1.posted_on, amount_cents: _1.amount_cents) }
      )
      by_id = candidates.index_by(&:id)
      pairs.transform_values { by_id.fetch(_1) }
    end
  end
end
