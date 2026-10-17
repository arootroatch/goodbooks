module AuditEventsHelper
  VERBS = { "create" => "created", "update" => "updated", "destroy" => "deleted" }.freeze

  def audit_action(event) = event.summary.presence || VERBS.fetch(event.action)

  def audit_value(name, value)
    return "—" if value.nil?
    return value if value == Audit::FILTERED
    return Money.new(value).to_s if name.to_s.end_with?("_cents") && value.is_a?(Integer)
    return value ? "Yes" : "No" if value == true || value == false

    value.is_a?(Array) ? value.join(", ") : value.to_s
  end

  def audit_type_options = Audit::MODELS.map { [ _1.constantize.model_name.human, _1 ] }.sort

  def audit_page_path(**cursor) = audit_events_path(request.query_parameters.except("before", "after").merge(cursor))
end
