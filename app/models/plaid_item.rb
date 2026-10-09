# One bank login connected through Plaid. Its accounts may feed different books.
class PlaidItem < ApplicationRecord
  belongs_to :household
  belongs_to :created_by, class_name: "User"
  has_many :accounts, dependent: :nullify

  encrypts :access_token

  enum :status, { ok: "ok", login_required: "login_required", error: "error" }, validate: true

  validates :institution_name, :item_id, :access_token, presence: true
  validates :item_id, uniqueness: true

  scope :manageable_by, ->(user) { user.household_owner? ? all : where(created_by: user) }

  def self.sync_all_later
    return unless PlaidGateway.enabled?

    ok.find_each { PlaidSyncJob.perform_later(_1) }
  end

  def manageable_by?(user) = user.household_owner? || created_by_id == user.id

  # Stops the feed: tells Plaid (best effort), turns the accounts back into CSV or manual ones, keeps every transaction.
  def disconnect!(gateway)
    warning = begin
      gateway.item_remove(access_token)
      nil
    rescue PlaidGateway::Error => e
      e.message
    end
    ApplicationRecord.transaction do
      accounts.each do |account|
        account.update!(source: account.csv_mapping.present? ? "csv" : "manual", plaid_item: nil, plaid_account_id: nil,
                        plaid_mask: nil, plaid_name: nil, plaid_sync_from: nil)
      end
      destroy!
    end
    warning
  end
end
