module SalesTax
  # Filing periods for a sales tax profile. Pure: dates in, periods out.
  class Calendar
    MONTHS = { "monthly" => 1, "quarterly" => 3, "annual" => 12 }.freeze

    Period = Data.define(:starts_on, :ends_on, :due_on) do
      def label
        months = (ends_on.year * 12 + ends_on.month) - (starts_on.year * 12 + starts_on.month) + 1
        case months
        when 1 then starts_on.strftime("%b %Y")
        when 3 then "Q#{(starts_on.month - 1) / 3 + 1} #{starts_on.year}"
        else starts_on.year.to_s
        end
      end
    end

    def self.due_on(ends_on, holidays: Holidays)
      date = ends_on.next_day.change(day: 20)
      date += 1 while date.saturday? || date.sunday? || holidays.for(date.year).include?(date)
      date
    end

    def initialize(starts_on:, frequency:, today:, holidays: Holidays)
      @months = MONTHS.fetch(frequency)
      @first = period_start(starts_on)
      @today = today
      @holidays = holidays
    end

    def periods
      starts = []
      start = @first
      while start <= @today
        starts << start
        start = start.advance(months: @months)
      end
      starts.map { build(_1) }
    end

    def period_for(date)
      start = period_start(date)
      start < @first ? nil : build(start)
    end

    def include_start?(date) = !date.nil? && date >= @first && period_start(date) == date

    private

    def period_start(date)
      Date.new(date.year, (date.month - 1) / @months * @months + 1, 1)
    end

    def build(start)
      ends_on = start.advance(months: @months) - 1
      Period.new(starts_on: start, ends_on: ends_on, due_on: self.class.due_on(ends_on, holidays: @holidays))
    end
  end
end
