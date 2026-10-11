class Account < ApplicationRecord
  belongs_to :business
  has_many :transactions, dependent: :restrict_with_error
  has_many :csv_imports, dependent: :destroy
  belongs_to :plaid_item, optional: true

  CSV_IMPORTABLE_SOURCES = %w[csv plaid].freeze

  enum :source, { manual: "manual", csv: "csv", plaid: "plaid" }, validate: true
  enum :kind, { checking: "checking", savings: "savings", credit: "credit", cash: "cash", other: "other" },
    validate: true, prefix: :kind

  scope :active, -> { where(archived_at: nil) }
  scope :csv_importable, -> { where(source: CSV_IMPORTABLE_SOURCES) }

  validates :name, presence: true
  validates :plaid_account_id, uniqueness: true, allow_nil: true
  validate :plaid_link_complete

  def mapping = CsvImport::Mapping.new(csv_mapping || {})

  def mapped? = csv_mapping.present?

  def archived? = archived_at.present?
  def archived = archived?

  def csv_importable? = CSV_IMPORTABLE_SOURCES.include?(source)

  private

  def plaid_link_complete
    linked = plaid_item.present? && plaid_account_id.present?
    if plaid? && !linked
      errors.add(:source, "plaid needs a Plaid connection")
    elsif !plaid? && (plaid_item.present? || plaid_account_id.present?)
      errors.add(:source, "must be plaid while linked to a Plaid connection")
    end
  end
end
