class AddPlaidToTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :transactions, :plaid_transaction_id, :string
    add_column :transactions, :review_reason, :string
    add_index :transactions, [ :account_id, :plaid_transaction_id ], unique: true, where: "plaid_transaction_id IS NOT NULL"
    add_index :transactions, :review_reason, where: "review_reason IS NOT NULL"
  end
end
