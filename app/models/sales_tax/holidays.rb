module SalesTax
  # The Tennessee state holidays that can delay a sales tax due date. Returns are due on the 20th, rolled past
  # weekends and holidays; only MLK Day (Jan 15–21), Presidents' Day (Feb 15–21), and Good Friday (Mar 20–Apr 23)
  # can land on a 20th. Every other TN holiday is a fixed date other than the 20th or falls nowhere near it.
  module Holidays
    module_function

    def for(year)
      [ nth_monday(year, 1, 3), nth_monday(year, 2, 3), easter(year) - 2 ]
    end

    def nth_monday(year, month, n)
      first = Date.new(year, month, 1)
      first + ((1 - first.wday) % 7) + 7 * (n - 1)
    end

    # Anonymous Gregorian algorithm (Meeus/Jones/Butcher).
    def easter(year)
      a = year % 19
      b, c = year.divmod(100)
      d, e = b.divmod(4)
      g = (8 * b + 13) / 25
      h = (19 * a + b - d - g + 15) % 30
      i, k = c.divmod(4)
      l = (32 + 2 * e + 2 * i - h - k) % 7
      m = (a + 11 * h + 22 * l) / 451
      month, day = (h + l - 7 * m + 114).divmod(31)
      Date.new(year, month, day + 1)
    end
  end
end
