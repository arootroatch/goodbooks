class AddTitheFlagsToAccountsAndTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :tithable, :boolean, null: false, default: true
    add_column :transactions, :tithe_excluded, :boolean, null: false, default: false
  end
end
