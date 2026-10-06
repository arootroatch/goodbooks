class Transaction < ApplicationRecord
  include MoneyAttribute

  CATEGORIZED_BY = %w[rule user].freeze

  money_attribute :amount
  attr_accessor :direction

  belongs_to :account
  belongs_to :category, optional: true
  belongs_to :rule, optional: true

  scope :inbox, -> { where(category_id: nil, transfer: false, excluded: false) }
  scope :countable, -> { where(transfer: false, excluded: false) }
  scope :for_businesses, ->(ids) { joins(:account).where(accounts: { business_id: ids }) }

  validates :posted_on, :payee, presence: true
  validates :amount_cents, presence: true, numericality: { only_integer: true }
  validates :categorized_by, inclusion: { in: CATEGORIZED_BY }, allow_nil: true
  validate :category_in_business

  before_validation :apply_direction
  before_validation :clear_category_for_transfer

  delegate :business, to: :account

  def inbox? = category_id.nil? && !transfer? && !excluded?

  def categorized_by_user? = categorized_by == "user"

  def rule_attributes = { payee: payee, memo: memo, amount_cents: amount_cents }

  private

  def apply_direction
    return if direction.blank? || amount_cents.nil?

    self.amount_cents = direction == "out" ? -amount_cents.abs : amount_cents.abs
  end

  def clear_category_for_transfer
    self.category = nil if transfer?
  end

  def category_in_business
    return if category.nil? || account.nil?

    errors.add(:category, "must belong to this business") if category.business_id != account.business_id
  end
end
