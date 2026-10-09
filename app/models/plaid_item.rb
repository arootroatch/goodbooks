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

    where.not(status: "login_required").find_each { PlaidSyncJob.perform_later(_1) }
  end

  # Items that need the user to log in again, for the dashboard banner.
  def self.needing_reconnect_for(user)
    return none unless PlaidGateway.enabled?

    visible = Account.where(business: user.accessible_businesses).select(:plaid_item_id)
    login_required.where(id: visible).or(login_required.manageable_by(user))
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
