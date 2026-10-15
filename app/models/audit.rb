# Writes AuditEvents for people's edits. Audited models call .record from their callbacks; nothing is written without an
# actor (so background jobs write nothing) or inside a .summarize block (which writes one summary event instead).
module Audit
  IGNORED = %w[id created_at updated_at].freeze
  SECRETS = %w[digest token secret otp password crypt salt].freeze
  FILTERED = "[FILTERED]".freeze
  MODELS = %w[Business Person Membership Invite Household Account Transaction Category Rule MileageEntry Client Invoice
              InvoicePayment SalesTaxProfile SalesTaxFiling TaxYear HomeOffice PersonAdjustment EstimatedPayment
              TaxParameters Goal PlaidItem].freeze

  Summary = Struct.new(:text, :record, :business, keyword_init: true)

  def self.as(user, &) = Current.set(audit_actor: user, &)

  def self.record(record, action)
    return if Current.actor.nil? || Current.audit_summary

    values = record.audit_values(action)
    return if action == "update" && values.empty?

    AuditEvent.create!(user: Current.actor, action:, auditable_type: record.class.name, auditable_id: record.id,
                       business_id: record.audit_business_id, label: label_for(record), changed_values: values)
  end

  def self.summarize(record: nil, business: nil)
    return yield(Summary.new) if Current.audit_summary

    summary = Summary.new(record:, business:)
    result = Current.set(audit_summary: summary) { yield summary }
    note(summary.text, record: summary.record, business: summary.business) if summary.text.present?
    result
  end

  def self.note(text, record: nil, business: nil)
    return if Current.actor.nil?

    business_id = business.is_a?(Business) ? business.id : business || record.try(:audit_business_id)
    AuditEvent.create!(user: Current.actor, action: "summary", summary: text, auditable_type: record&.class&.name,
                       auditable_id: record&.id, business_id:, label: label_for(record))
  end

  def self.filter(values)
    values.to_h { |name, pair| [ name, SECRETS.any? { name.to_s.include?(_1) } ? [ FILTERED, FILTERED ] : pair ] }
  end

  def self.label_for(record)
    return "" if record.nil?

    (record.try(:audit_label) || record.try(:name) || "#{record.model_name.human} ##{record.id}").to_s.truncate(255)
  end

  private_class_method :label_for
end
