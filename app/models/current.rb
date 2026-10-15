class Current < ActiveSupport::CurrentAttributes
  attribute :session, :audit_actor, :audit_summary
  delegate :user, to: :session, allow_nil: true

  # Who an audit event is attributed to: an explicit override (sign-up, setup), else the signed-in user.
  def actor = audit_actor || user
end
