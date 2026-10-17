class AuditEvent < ApplicationRecord
  ACTIONS = %w[create update destroy summary].freeze

  belongs_to :user
  belongs_to :business, optional: true

  validates :action, inclusion: { in: ACTIONS }

  before_destroy { raise ActiveRecord::ReadOnlyRecord, "Audit events can't be deleted" }

  def readonly? = persisted? || super

  def self.filtered(user_id: nil, auditable_type: nil, auditable_id: nil, business_id: nil, range: nil)
    scope = all
    scope = scope.where(user_id:) if user_id.present?
    scope = scope.where(auditable_type:) if auditable_type.present?
    scope = scope.where(auditable_id:) if auditable_id.present?
    scope = scope.where(business_id:) if business_id.present?
    scope = scope.where(created_at: range.first.in_time_zone..range.last.in_time_zone.end_of_day) if range
    scope
  end
end
