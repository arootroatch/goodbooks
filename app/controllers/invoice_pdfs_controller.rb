# Streams the PDF after the business access check; Active Storage's public blob routes are disabled.
class InvoicePdfsController < ApplicationController
  include BusinessScoped
  include BusinessKindOnly

  def show
    invoice = @business.invoices.find(params[:invoice_id])
    return head :not_found unless invoice.pdf.attached?

    send_data invoice.pdf.download, filename: invoice.pdf.filename.to_s, type: "application/pdf", disposition: :inline
  end
end
