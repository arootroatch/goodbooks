module Tax
  # Estimated tax installments are due Apr 15, Jun 15, Sep 15, and Jan 15, rolled past weekends and holidays. Only two holidays
  # can land on a roll date: MLK Day (third Monday of January, Jan 15–21) and DC Emancipation Day observed (Apr 15–17).
  module DueDates
    module_function

    def for(year)
      [ Date.new(year, 4, 15), Date.new(year, 6, 15), Date.new(year, 9, 15), Date.new(year + 1, 1, 15) ].map { roll(_1) }
    end

    def roll(date)
      date += 1 while date.saturday? || date.sunday? || holiday?(date)
      date
    end

    def quarter_on(year, date)
      (self.for(year).index { date <= _1 } || 3) + 1
    end

    def holiday?(date) = mlk_day?(date) || emancipation_day_observed?(date)

    def mlk_day?(date) = date.month == 1 && date.monday? && (15..21).cover?(date.day)

    def emancipation_day_observed?(date)
      return false unless date.month == 4

      day = Date.new(date.year, 4, 16)
      day -= 1 if day.saturday?
      day += 1 if day.sunday?
      date == day
    end
  end
end
