module InvoicesHelper
  STATUS_BADGES = { "paid" => "badge-pos", "overdue" => "badge-neg", "draft" => "badge-muted", "void" => "badge-muted" }.freeze

  def invoice_status_badge(invoice)
    status = invoice.display_status
    tag.span(status.humanize, class: [ "badge", STATUS_BADGES[status] ])
  end

  def invoice_outstanding(invoice)
    invoice.sent? || invoice.paid? ? money(invoice.outstanding_cents) : "—"
  end

  def invoice_status_filter_options
    [ [ "All statuses", "" ] ] + InvoiceFilter::STATUSES.map { |value, label| [ label, value ] }
  end

  def invoice_client_options(business, invoice)
    clients = business.clients.where(archived_at: nil).or(business.clients.where(id: invoice.client_id)).order(:name)
    selected = (params.dig(:invoice, :client_id) || invoice.client_id).to_s
    options_for_select(clients.map { [ _1.name, _1.id.to_s ] } + [ [ "New client…", "new" ] ], selected)
  end
end
