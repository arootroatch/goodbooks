class HouseholdInvoiceAgingsController < ApplicationController
  include InvoiceAgingReport

  before_action :require_household_access!

  def show
    @csv_path = household_invoice_aging_path(format: :csv)
    render_aging(Invoice.where(business_id: Business.business_kind.select(:id)), title: "Aging: all businesses", filename: "household")
  end
end
