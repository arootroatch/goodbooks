# Shared by the business and household aging screens; they differ only in which invoices they pass in.
module InvoiceAgingReport
  private

  def render_aging(invoices, title:, filename:)
    today = @as_of = Date.current
    open_invoices = invoices.sent.includes(:client, :business, :payments).to_a.select { _1.outstanding_cents.positive? }
    @report = Reports::InvoiceAging.new(Reports::InvoiceAging.rows_from(open_invoices), as_of: today)
    @title = title
    respond_to do |format|
      format.html { render "invoice_agings/show" }
      format.csv do
        send_data Reports::InvoiceAgingCsv.generate(@report, as_of: today), filename: "#{filename}-aging-#{today}.csv", type: "text/csv"
      end
    end
  end
end
