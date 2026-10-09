class SalesTaxPeriodsController < ApplicationController
  include BusinessScoped
  include BusinessKindOnly
  include SalesTaxPeriodLookup

  def show
    @report = SalesTax.report_for(@business, find_sales_tax_period(params[:starts_on]))
    respond_to do |format|
      format.html
      format.csv do
        send_data Reports::SalesTaxPeriodCsv.generate(@report),
          filename: "#{@business.name.parameterize}-sales-tax-#{@report.period.starts_on}.csv", type: "text/csv"
      end
    end
  end
end
