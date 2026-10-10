# Finds open invoices whose outstanding balance equals an inbox deposit's amount.
class InvoiceMatcher
  LIMIT = 3

  def self.for_businesses(business_ids)
    new(Invoice.sent.where(business_id: business_ids).includes(:client, :payments).to_a)
  end

  def initialize(invoices)
    @index = invoices.select { _1.outstanding_cents.positive? }.group_by { [ _1.business_id, _1.outstanding_cents ] }
  end

  def for(txn, business_id)
    return [] unless txn.amount_cents.positive?

    @index.fetch([ business_id, txn.amount_cents ], []).sort_by { [ _1.due_date, _1.id ] }.first(LIMIT)
  end
end
