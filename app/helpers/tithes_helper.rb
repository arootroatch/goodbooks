module TithesHelper
  def tithe_balance_label(cents)
    if cents.positive? then "Behind #{money(cents)}"
    elsif cents.negative? then "Ahead #{money(-cents)}"
    else "Even"
    end
  end

  def tithe_week_label(week) = "#{week.starts_on.strftime("%b %-d")} – #{week.ends_on.strftime("%b %-d, %Y")}"
end
