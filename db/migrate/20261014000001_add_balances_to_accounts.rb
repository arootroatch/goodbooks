class AddBalancesToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :opening_balance_cents, :integer
    add_column :accounts, :opening_balance_on, :date
    add_column :accounts, :reported_balance_cents, :integer
    add_column :accounts, :balance_reported_at, :datetime
  end
end
