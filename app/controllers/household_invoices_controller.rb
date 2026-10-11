class HouseholdInvoicesController < ApplicationController
  include ScalarParams

  household_page
  before_action :require_household_access!

  def show
    invoices = Invoice.where(business_id: Business.business_kind.select(:id))
    @filter = InvoiceFilter.new(invoices, scalar_params(:status, :from, :to, :page))
    respond_to do |format|
      format.html do
        @invoices = @filter.results
        @open = Invoices::OpenSummary.for(invoices)
      end
      format.csv { send_data Reports::InvoiceCsv.generate(@filter.all), filename: "household-invoices-#{Date.current}.csv", type: "text/csv" }
    end
  end
end
