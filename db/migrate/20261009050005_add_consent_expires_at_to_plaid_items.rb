class AddConsentExpiresAtToPlaidItems < ActiveRecord::Migration[8.1]
  def change
    add_column :plaid_items, :consent_expires_at, :datetime
  end
end
