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

  # Items that are broken or due for renewal, for the dashboard banner.
  def self.needing_reconnect_for(user)
    return none unless PlaidGateway.enabled?

    visible = Account.where(business: user.accessible_businesses).select(:plaid_item_id)
    needing_renewal = login_required.or(where.not(consent_expires_at: nil))
    needing_renewal.where(id: visible).or(needing_renewal.manageable_by(user))
  end

  def reconnectable? = login_required? || error? || consent_expires_at.present?

  def manageable_by?(user) = user.household_owner? || created_by_id == user.id

  # Stops the feed: turns the accounts back into CSV or manual ones, keeps every transaction, then tells Plaid
  # (best effort, after the local commit so a local failure leaves the item connected at Plaid).
  def disconnect!(gateway)
    token = access_token
    ApplicationRecord.transaction do
      accounts.each do |account|
        account.update!(source: account.csv_mapping.present? ? "csv" : "manual", plaid_item: nil, plaid_account_id: nil,
                        plaid_mask: nil, plaid_name: nil, plaid_sync_from: nil)
      end
      destroy!
    end
    begin
      gateway.item_remove(token)
      nil
    rescue PlaidGateway::Error => e
      e.message
    end
  end
end
