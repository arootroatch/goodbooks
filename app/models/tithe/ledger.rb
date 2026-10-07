module Tithe
  # Weekly tithe owed vs. paid (spec §4). Pure: entries in, Sunday–Saturday weeks out.
  # Owed is 10% of each week's income, rounded once per week. Payments settle the oldest weeks first;
  # the running balance uses actual payment dates. Positive balance = behind.
  class Ledger
    RATE = Rational(1, 10)
    Entry = Data.define(:posted_on, :cents, :kind, :source)
    Week = Data.define(:starts_on, :ends_on, :income_cents, :owed_cents, :paid_cents, :paid_toward_cents, :status, :balance_cents, :entries)

    attr_reader :weeks, :owed_cents, :paid_cents, :balance_cents, :credit_cents, :ytd_owed_cents, :ytd_paid_cents

    def self.week_start(date) = date - date.wday

    def initialize(entries:, start_on:, today:)
      by_week = entries.select { _1.posted_on.between?(start_on, today) }.group_by { self.class.week_start(_1.posted_on) }
      starts = start_on > today ? [] : self.class.week_start(start_on).step(self.class.week_start(today), 7).to_a
      @owed_cents = 0
      @paid_cents = 0
      totals = starts.map do |starts_on|
        week_entries = (by_week[starts_on] || []).sort_by(&:posted_on)
        income = week_entries.select { _1.kind == :income }.sum(&:cents)
        paid = week_entries.select { _1.kind == :payment }.sum(&:cents)
        owed = Money.round_rational(income * RATE)
        @owed_cents += owed
        @paid_cents += paid
        { starts_on:, income:, owed:, paid:, balance: @owed_cents - @paid_cents, entries: week_entries }
      end
      @balance_cents = @owed_cents - @paid_cents
      @credit_cents = [ -@balance_cents, 0 ].max
      @weeks = allocate(totals, [ @paid_cents, 0 ].max)
      this_year = @weeks.select { _1.ends_on.year == today.year }
      @ytd_owed_cents = this_year.sum(&:owed_cents)
      @ytd_paid_cents = this_year.sum(&:paid_cents)
    end

    private

    def allocate(totals, remaining)
      totals.map do |w|
        toward = [ w[:owed], remaining ].min
        remaining -= toward
        Week.new(starts_on: w[:starts_on], ends_on: w[:starts_on] + 6, income_cents: w[:income], owed_cents: w[:owed],
                 paid_cents: w[:paid], paid_toward_cents: toward, status: status_for(w[:owed], toward),
                 balance_cents: w[:balance], entries: w[:entries])
      end
    end

    def status_for(owed, toward)
      if toward == owed then "paid"
      elsif toward.positive? then "partial"
      else "open"
      end
    end
  end
end
