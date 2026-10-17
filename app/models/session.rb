class Session < ApplicationRecord
  TOUCH_INTERVAL = 5.minutes

  belongs_to :user

  before_create { self.last_seen_at ||= Time.current }

  def seen!
    update_column(:last_seen_at, Time.current) if last_seen_at.nil? || last_seen_at < TOUCH_INTERVAL.ago
  end

  def device_label = UserAgentLabel.call(user_agent)
end
