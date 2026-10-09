# Resolves a period from its start date through the business's calendar; anything else is 404.
module SalesTaxPeriodLookup
  private

  def find_sales_tax_period(param)
    raise ActiveRecord::RecordNotFound unless @business.collects_sales_tax?

    starts_on = Date.iso8601(param.to_s)
    @business.sales_tax_profile.calendar.periods.find { _1.starts_on == starts_on } || raise(ActiveRecord::RecordNotFound)
  rescue Date::Error
    raise ActiveRecord::RecordNotFound
  end
end
