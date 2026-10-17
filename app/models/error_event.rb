class ErrorEvent < ApplicationRecord
  scope :unresolved, -> { where(resolved_at: nil) }
  scope :resolved, -> { where.not(resolved_at: nil) }
  scope :recent_first, -> { order(last_seen_at: :desc) }
end
