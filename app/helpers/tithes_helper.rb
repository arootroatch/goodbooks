module TithesHelper
  STATUS_BADGES = { "paid" => "badge-pos", "partial" => "badge-warn", "open" => "badge-muted" }.freeze

  def tithe_balance_label(cents)
    if cents.positive? then "Behind #{money(cents)}"
    elsif cents.negative? then "Ahead #{money(-cents)}"
    else "Even"
    end
  end

  def tithe_status_badge(status) = tag.span(status.humanize, class: [ "badge", STATUS_BADGES[status] ])

  def tithe_week_label(week) = "#{week.starts_on.strftime("%b %-d")} – #{week.ends_on.strftime("%b %-d, %Y")}"
end
