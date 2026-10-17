# Records creates, updates and destroys through Audit. Declare a label and, when the book isn't business_id, how to find it:
#   audited label: -> { name }, business: -> { account&.business_id }, ignore: %w[cursor]
module Audited
  extend ActiveSupport::Concern

  included do
    class_attribute :audit_options, instance_writer: false, default: {}
    after_create { Audit.record(self, "create") }
    after_update { Audit.record(self, "update") }
    after_destroy { Audit.record(self, "destroy") }
  end

  class_methods do
    def audited(label: nil, business: nil, ignore: [])
      self.audit_options = { label:, business:, ignore: ignore.map(&:to_s) }
    end
  end

  def audit_label
    audit_options[:label] ? instance_exec(&audit_options[:label]).to_s : "#{model_name.human} ##{id}"
  end

  def audit_business_id
    return instance_exec(&audit_options[:business]) if audit_options[:business]

    business_id if has_attribute?(:business_id)
  end

  def audit_values(action)
    pairs = case action
    when "update" then saved_changes
    when "create" then attributes.compact.transform_values { [ nil, _1 ] }
    when "destroy" then attributes.compact.transform_values { [ _1, nil ] }
    end
    Audit.filter(pairs.except(*Audit::IGNORED, *audit_options.fetch(:ignore, [])).merge(audit_extra_values(action)))
  end

  private

  def audit_extra_values(_action) = {}
end
