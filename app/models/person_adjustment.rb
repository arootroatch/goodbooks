class PersonAdjustment < ApplicationRecord
  include Audited
  audited label: -> { "#{person&.name} adjustments #{year}" }
  include MoneyAttribute

  PLANS = { "sep" => "SEP-IRA", "solo_401k" => "Solo 401(k)" }.freeze

  belongs_to :person

  money_attribute :se_health_insurance, allow_blank: true
  money_attribute :retirement_contribution, allow_blank: true

  before_validation do
    self.se_health_insurance_cents ||= 0
    self.retirement_contribution_cents ||= 0
    self.retirement_plan = nil if retirement_plan.blank?
  end

  validates :year, numericality: { only_integer: true, in: 2000..2100 }, uniqueness: { scope: :person_id }
  validates :retirement_plan, inclusion: { in: PLANS.keys }, allow_nil: true
  validates :retirement_plan, presence: { message: "is required with a contribution" }, if: -> { retirement_contribution_cents.to_i.positive? }
  validates :se_health_insurance_cents, :retirement_contribution_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
end
