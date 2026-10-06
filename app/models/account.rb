class Account < ApplicationRecord
  belongs_to :business
  has_many :transactions, dependent: :restrict_with_error
  has_many :csv_imports, dependent: :destroy

  enum :source, { manual: "manual", csv: "csv", plaid: "plaid" }, validate: true
  enum :kind, { checking: "checking", savings: "savings", credit: "credit", cash: "cash", other: "other" },
    validate: true, prefix: :kind

  scope :active, -> { where(archived_at: nil) }

  validates :name, presence: true

  def mapping = CsvImport::Mapping.new(csv_mapping || {})

  def mapped? = csv_mapping.present?

  def archived? = archived_at.present?
  def archived = archived?
end
