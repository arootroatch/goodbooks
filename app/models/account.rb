class Account < ApplicationRecord
  include MoneyAttribute

  belongs_to :business
  has_many :transactions, dependent: :restrict_with_error
  has_many :csv_imports, dependent: :destroy
  has_many :goals, dependent: :restrict_with_error
  belongs_to :plaid_item, optional: true

  CSV_IMPORTABLE_SOURCES = %w[csv plaid].freeze

  enum :source, { manual: "manual", csv: "csv", plaid: "plaid" }, validate: true
  enum :kind, { checking: "checking", savings: "savings", credit: "credit", cash: "cash", other: "other" },
    validate: true, prefix: :kind

  money_attribute :opening_balance, allow_blank: true

  scope :active, -> { where(archived_at: nil) }
  scope :csv_importable, -> { where(source: CSV_IMPORTABLE_SOURCES) }

  validates :name, presence: true
  validates :plaid_account_id, uniqueness: true, allow_nil: true
  validate :plaid_link_complete
  validate :opening_balance_complete

  def mapping = CsvImport::Mapping.new(csv_mapping || {})

  def mapped? = csv_mapping.present?

  def archived? = archived_at.present?
  def archived = archived?

  def csv_importable? = CSV_IMPORTABLE_SOURCES.include?(source)

  # Plaid: what the bank reported at the last sync. Manual/CSV: the opening balance plus every non-excluded
  # transaction after its date (rows on the date are already in it). Nil when unknown.
  def balance_cents
    return reported_balance_cents if plaid?
    return if opening_balance_cents.nil? || opening_balance_on.nil?

    opening_balance_cents + transactions.where(excluded: false).where("posted_on > ?", opening_balance_on).sum(:amount_cents)
  end

  def balance_known? = !balance_cents.nil?

  private

  def plaid_link_complete
    linked = plaid_item.present? && plaid_account_id.present?
    if plaid? && !linked
      errors.add(:source, "plaid needs a Plaid connection")
    elsif !plaid? && (plaid_item.present? || plaid_account_id.present?)
      errors.add(:source, "must be plaid while linked to a Plaid connection")
    end
  end

  def opening_balance_complete
    return if errors[:opening_balance].any?

    if opening_balance_cents && opening_balance_on.nil?
      errors.add(:opening_balance_on, "can't be blank with an opening balance")
    elsif opening_balance_cents.nil? && opening_balance_on
      errors.add(:opening_balance, "can't be blank with an as-of date")
    end
  end
end
