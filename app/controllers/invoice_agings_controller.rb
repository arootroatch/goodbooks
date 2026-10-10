class InvoiceAgingsController < ApplicationController
  include BusinessScoped
  include BusinessKindOnly
  include InvoiceAgingReport

  def show
    @csv_path = business_invoice_aging_path(@business, format: :csv)
    render_aging(@business.invoices, title: "Aging: #{@business.name}", filename: @business.name.parameterize)
  end
end
