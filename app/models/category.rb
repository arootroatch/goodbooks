class Category < ApplicationRecord
  belongs_to :business

  enum :kind, { income: "income", expense: "expense" }, validate: true

  scope :active, -> { where(archived_at: nil) }

  validates :name, presence: true, uniqueness: { scope: :business_id }
  validates :deductible_bps, numericality: { only_integer: true, in: 0..10_000 }
  validate :schedule_c_line_matches_kind
  validate :deductible_percent_parses

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

  private

  def schedule_c_line_matches_kind
    allowed = ScheduleC.options_for(kind).map(&:last)
    errors.add(:schedule_c_line, "is not valid for #{kind} categories") unless allowed.include?(schedule_c_line)
  end

  def deductible_percent_parses
    errors.add(:deductible_percent, "is not a number") if @deductible_percent_invalid
  end
end
