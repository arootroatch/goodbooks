class Category < ApplicationRecord
  SALES_TAX_TREATMENTS = %w[taxable exempt not_a_sale].freeze
  SALES_TAX_TREATMENT_LABELS = { "taxable" => "Taxable sales", "exempt" => "Exempt sales", "not_a_sale" => "Not a sale" }.freeze

  belongs_to :business

  enum :kind, { income: "income", expense: "expense", sales_tax_remittance: "sales_tax_remittance" }, validate: true

  scope :active, -> { where(archived_at: nil) }
  scope :gross_receipts, -> { active.income.where(schedule_c_line: "1") }
  scope :taxable_gross_receipts, -> { gross_receipts.where(sales_tax_treatment: "taxable") }

  validates :name, presence: true, uniqueness: { scope: :business_id }
  validates :deductible_bps, numericality: { only_integer: true, in: 0..10_000 }
  validates :sales_tax_treatment, inclusion: { in: SALES_TAX_TREATMENTS }, allow_nil: true
  validates :processor_fees, uniqueness: { scope: :business_id, message: "is already set on another category" }, if: :processor_fees?
  before_validation :normalize_tithe_flags
  before_validation :normalize_sales_tax_fields

  validate :schedule_c_line_matches_kind
  validate :tithe_flags_only_on_personal
  validate :remittance_only_on_business_books
  validate :one_active_remittance_category
  validate :processor_fees_only_on_business_expense
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

  def taxable? = income? && sales_tax_treatment == "taxable"
  def sale? = income? && %w[taxable exempt].include?(sales_tax_treatment)

  private

  def schedule_c_line_matches_kind
    if business&.personal?
      errors.add(:schedule_c_line, "must be blank for personal categories") if schedule_c_line.present?
      return
    end
    return if sales_tax_remittance?

    allowed = ScheduleC.options_for(kind).map(&:last)
    errors.add(:schedule_c_line, "is not valid for #{kind} categories") unless allowed.include?(schedule_c_line)
  end

  # Tithable only means something on income, tithe only on expense; the form shows both, so normalize instead of erroring.
  def normalize_tithe_flags
    self.tithable = true if expense?
    self.tithe = false if income?
  end

  # Taxability is only meaningful on business income; a remittance is never on Schedule C.
  def normalize_sales_tax_fields
    if income? && business&.business?
      self.sales_tax_treatment = sales_tax_treatment.presence || (schedule_c_line == "1" ? "taxable" : "not_a_sale")
    else
      self.sales_tax_treatment = nil
    end
    self.schedule_c_line = nil if sales_tax_remittance?
  end

  def remittance_only_on_business_books
    errors.add(:kind, "can't be a sales tax remittance on the personal book") if sales_tax_remittance? && business&.personal?
  end

  def one_active_remittance_category
    return unless sales_tax_remittance? && archived_at.nil? && business
    return unless business.categories.sales_tax_remittance.active.where.not(id: id).exists?

    errors.add(:kind, "already has a sales tax remittance category")
  end

  def processor_fees_only_on_business_expense
    return unless processor_fees? && (!expense? || business&.personal?)

    errors.add(:processor_fees, "only applies to business expense categories")
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
