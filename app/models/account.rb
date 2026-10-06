class Account < ApplicationRecord
  belongs_to :business

  enum :source, { manual: "manual", csv: "csv", plaid: "plaid" }, validate: true
  enum :kind, { checking: "checking", savings: "savings", credit: "credit", cash: "cash", other: "other" },
    validate: true, prefix: :kind

  scope :active, -> { where(archived_at: nil) }

  validates :name, presence: true

  def archived? = archived_at.present?
end
