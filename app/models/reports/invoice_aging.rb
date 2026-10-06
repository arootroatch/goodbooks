module Reports
  class InvoiceAging
    Row = Data.define(:invoice_id, :number, :client_name, :business_name, :due_date, :outstanding_cents)
    Bucket = Data.define(:key, :label, :rows, :total_cents)
    BUCKETS = [ [ "current", "Current" ], [ "days_1_30", "1–30 days" ], [ "days_31_60", "31–60 days" ], [ "over_60", "Over 60 days" ] ].freeze

    attr_reader :buckets, :total_cents

    def self.days_past_due(due_date, as_of) = [ (as_of - due_date).to_i, 0 ].max

    def self.bucket_key(days)
      if days <= 0 then "current"
      elsif days <= 30 then "days_1_30"
      elsif days <= 60 then "days_31_60"
      else "over_60"
      end
    end

    def self.rows_from(invoices)
      invoices.map do |invoice|
        Row.new(invoice_id: invoice.id, number: invoice.number, client_name: invoice.client.name,
                business_name: invoice.business.name, due_date: invoice.due_date, outstanding_cents: invoice.outstanding_cents)
      end
    end

    def initialize(rows, as_of:)
      grouped = rows.group_by { self.class.bucket_key(self.class.days_past_due(_1.due_date, as_of)) }
      @buckets = BUCKETS.map do |key, label|
        list = (grouped[key] || []).sort_by { [ _1.due_date, _1.number ] }
        Bucket.new(key: key, label: label, rows: list, total_cents: list.sum(&:outstanding_cents))
      end
      @total_cents = @buckets.sum(&:total_cents)
    end
  end
end
