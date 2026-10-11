class Category < ApplicationRecord
  belongs_to :business

  enum :kind, { income: "income", expense: "expense" }, validate: true

  scope :active, -> { where(archived_at: nil) }
  scope :gross_receipts, -> { active.income.where(schedule_c_line: "1") }

  validates :name, presence: true, uniqueness: { scope: :business_id }
  validates :deductible_bps, numericality: { only_integer: true, in: 0..10_000 }
  before_validation :normalize_tithe_flags

  validate :schedule_c_line_matches_kind
  validate :tithe_flags_only_on_personal
  validate :deductible_percent_parses
  validate :kind_stays_income_while_linked, on: :update

  def deductible_percent
    return @deductible_percent_input if defined?(@deductible_percent_input)

    value = Rational(deductible_bps.to_i, 100)
    value.denominator == 1 ? value.to_i.to_s : format("%.2f", value)
  end

  def deductible_percent=(input)
    @deductible_percent_input = input
    @deductible_percent_invalid = false
    stripped = input.to_s.strip
    unless stripped.match?(/\A\d{1,3}(\.\d{1,2})?\z/)
      @deductible_percent_invalid = true
      return
    end
    self.deductible_bps = (Rational(stripped) * 100).round
  rescue ArgumentError, ZeroDivisionError
    @deductible_percent_invalid = true
  end

  def archived? = archived_at.present?

  def archived = archived?

  def gross_receipts? = income? && schedule_c_line == "1" && !archived?

  private

  def schedule_c_line_matches_kind
    if business&.personal?
      errors.add(:schedule_c_line, "must be blank for personal categories") if schedule_c_line.present?
      return
    end

    allowed = ScheduleC.options_for(kind).map(&:last)
    errors.add(:schedule_c_line, "is not valid for #{kind} categories") unless allowed.include?(schedule_c_line)
  end

  # Tithable only means something on income, tithe only on expense; the form shows both, so normalize instead of erroring.
  def normalize_tithe_flags
    self.tithable = true if expense?
    self.tithe = false if income?
  end

  def tithe_flags_only_on_personal
    return if business&.personal? || (tithable? && !tithe?)

    errors.add(:base, "Tithe settings are only for personal categories")
  end

  def kind_stays_income_while_linked
    return unless kind_changed? && kind_was == "income"
    return unless InvoicePayment.joins(:deposit).exists?(transactions: { category_id: id })

    errors.add(:kind, "can't change while deposits in this category are linked to invoices")
  end

  def deductible_percent_parses
    errors.add(:deductible_percent, "is not a number") if @deductible_percent_invalid
  end
end
