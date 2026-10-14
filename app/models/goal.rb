# A money goal in one book. Payment goals add up the outflows linked to them (by their matcher or by hand);
# savings goals share their account's balance with the book's other savings goals on it, in position order.
class Goal < ApplicationRecord
  include MoneyAttribute

  KINDS = %w[payments savings].freeze
  MatcherRule = Data.define(:field, :operator, :value, :amount_min_cents, :amount_max_cents)

  money_attribute :target
  money_attribute :match_amount_min, allow_blank: true
  money_attribute :match_amount_max, allow_blank: true

  belongs_to :business
  belongs_to :account, optional: true
  has_many :transactions, dependent: nil

  scope :active, -> { where(archived_at: nil) }
  scope :ordered, -> { order(:position, :id) }
  scope :payments, -> { where(kind: "payments") }
  scope :savings, -> { where(kind: "savings") }

  validates :name, presence: true, length: { maximum: 100 }
  validates :kind, inclusion: { in: KINDS }
  validates :target_cents, numericality: { greater_than: 0 }, if: -> { errors[:target].empty? && target_cents }
  validates :match_field, inclusion: { in: Rule::FIELDS }, allow_nil: true
  validates :match_operator, inclusion: { in: Rule::OPERATORS }, allow_nil: true
  validates :match_value, length: { maximum: 100 }
  validates :match_amount_min_cents, :match_amount_max_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :matcher_complete
  validate :amount_range_ordered
  validate :savings_account_usable
  validate :kind_unchanged, on: :update

  before_validation :clear_other_kind_fields
  before_create { self.position = (business.goals.maximum(:position) || 0) + 1 }

  def payments? = kind == "payments"
  def savings? = kind == "savings"
  def archived? = archived_at.present?
  def archived = archived?

  def matcher? = payments? && match_field.present? && match_operator.present? && match_value.present?

  def matcher_rule
    MatcherRule.new(field: match_field, operator: match_operator, value: match_value,
                    amount_min_cents: match_amount_min_cents, amount_max_cents: match_amount_max_cents)
  end

  def matcher_description
    amounts = [ match_amount_min_cents && "≥ #{Money.new(match_amount_min_cents)}",
                match_amount_max_cents && "≤ #{Money.new(match_amount_max_cents)}" ].compact
    [ "#{match_field} #{match_operator.to_s.humanize(capitalize: false)} \"#{match_value}\"", *amounts ].join(" · ")
  end

  private

  def clear_other_kind_fields
    if savings?
      self.match_field = self.match_operator = self.match_value = nil
      self.match_amount_min_cents = self.match_amount_max_cents = nil
    else
      self.account = nil
      self.match_value = match_value.presence
      self.match_field = match_field.presence
      self.match_operator = match_operator.presence
    end
  end

  def matcher_complete
    return unless payments?

    parts = [ match_field, match_operator, match_value ]
    errors.add(:match_value, "needs a field, an operator and a value") if parts.any?(&:present?) && !parts.all?(&:present?)
  end

  def amount_range_ordered
    return unless match_amount_min_cents && match_amount_max_cents && match_amount_min_cents > match_amount_max_cents

    errors.add(:match_amount_min, "must be less than or equal to the maximum")
  end

  def savings_account_usable
    return unless savings?
    return errors.add(:account, "can't be blank") if account.nil?

    if account.business_id != business_id then errors.add(:account, "must belong to this book")
    elsif account.archived? then errors.add(:account, "is archived")
    elsif account.kind_credit? then errors.add(:account, "can't be a credit account")
    end
  end

  def kind_unchanged
    errors.add(:kind, "can't be changed") if will_save_change_to_kind?
  end
end
