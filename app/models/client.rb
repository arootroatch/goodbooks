class Client < ApplicationRecord
  belongs_to :business
  has_many :invoices, dependent: :restrict_with_error

  scope :active, -> { where(archived_at: nil) }

  validates :name, presence: true, length: { maximum: 200 }, uniqueness: { scope: :business_id }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :notes, length: { maximum: 2_000 }

  def archived? = archived_at.present?
  def archived = archived?
end
