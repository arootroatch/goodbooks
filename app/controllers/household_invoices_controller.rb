class HouseholdInvoicesController < ApplicationController
  include ScalarParams

  household_page
  before_action :require_household_access!

  def show
    @filter = InvoiceFilter.new(Invoice.where(business_id: Business.select(:id)), scalar_params(:status, :from, :to, :page))
    respond_to do |format|
      format.html { @invoices = @filter.results }
      format.csv { send_data Reports::InvoiceCsv.generate(@filter.all), filename: "household-invoices-#{Date.current}.csv", type: "text/csv" }
    end
  end
end
