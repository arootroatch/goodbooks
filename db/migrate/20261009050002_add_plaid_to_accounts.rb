class AddPlaidToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_reference :accounts, :plaid_item, foreign_key: true
    add_column :accounts, :plaid_account_id, :string
    add_column :accounts, :plaid_mask, :string
    add_column :accounts, :plaid_name, :string
    add_column :accounts, :plaid_sync_from, :date
    add_index :accounts, :plaid_account_id, unique: true, where: "plaid_account_id IS NOT NULL"
  end
end
