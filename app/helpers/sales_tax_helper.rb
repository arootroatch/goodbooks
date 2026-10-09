module SalesTaxHelper
  def sales_tax_status_badge(report)
    tag.span(report.status.humanize, class: "badge badge-#{report.status}")
  end

  def sales_tax_due_label(period)
    period.due_on.strftime("%b %-d, %Y")
  end

  def sales_tax_period_options(business)
    profile = business.sales_tax_profile
    return [] unless profile

    profile.calendar.periods.reverse.map { [ _1.label, _1.starts_on.iso8601 ] }
  end
end
