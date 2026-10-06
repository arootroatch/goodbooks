class Rule < ApplicationRecord
  include MoneyAttribute

  FIELDS = %w[payee memo].freeze
  OPERATORS = %w[contains equals starts_with].freeze
  OUTCOMES = %w[categorize transfer].freeze

  money_attribute :amount_min, allow_blank: true
  money_attribute :amount_max, allow_blank: true

  belongs_to :business
  belongs_to :category, optional: true
  has_many :transactions, dependent: :nullify

  scope :ordered, -> { order(:position) }
  scope :applicable, -> { left_joins(:category).where("rules.outcome = 'transfer' OR categories.archived_at IS NULL") }

  validates :field, inclusion: { in: FIELDS }
  validates :operator, inclusion: { in: OPERATORS }
  validates :outcome, inclusion: { in: OUTCOMES }
  validates :value, presence: true
  validates :category, presence: true, if: -> { outcome == "categorize" }
  validates :amount_min_cents, :amount_max_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :category_in_business

  before_validation { self.category = nil if outcome == "transfer" }
  before_create { self.position = (business.rules.maximum(:position) || 0) + 1 }

  def move_to!(new_position)
    ApplicationRecord.transaction do
      ids = business.rules.ordered.where.not(id: id).pluck(:id)
      ids.insert(new_position.to_i.clamp(1, ids.size + 1) - 1, id)
      ids.each.with_index(1) { |rule_id, position| Rule.where(id: rule_id).update_all(position: position) }
    end
    reload
  end

  def inactive? = outcome == "categorize" && category&.archived? == true

  def description
    target = outcome == "transfer" ? "Transfer" : category&.name
    "#{field} #{operator.humanize(capitalize: false)} \"#{value}\" → #{target}"
  end

  private

  def category_in_business
    errors.add(:category, "must belong to this business") if category && category.business_id != business_id
  end
end
