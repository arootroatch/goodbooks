class CsvImport::Mapping
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :skip_rows, :integer, default: 0
  attribute :date_column, :string
  attribute :date_format, :string, default: "MM/DD/YYYY"
  attribute :payee_column, :string
  attribute :memo_column, :string
  attribute :amount_column, :string
  attribute :debit_column, :string
  attribute :credit_column, :string
  attribute :invert_sign, :boolean, default: false

  validates :date_column, :payee_column, presence: true
  validates :date_format, inclusion: { in: CsvImport::Parser::DATE_FORMATS.keys }
  validates :skip_rows, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :one_amount_style

  def columns
    [date_column, payee_column, memo_column, amount_column, debit_column, credit_column].compact_blank
  end

  def to_h = attributes

  private

  def one_amount_style
    single = amount_column.present?
    split = debit_column.present? && credit_column.present?
    partial = debit_column.present? ^ credit_column.present?
    return if (single ^ split) && !partial

    errors.add(:base, "Choose an amount column, or both a debit and a credit column")
  end
end
