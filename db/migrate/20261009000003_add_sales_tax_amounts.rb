class AddSalesTaxAmounts < ActiveRecord::Migration[8.1]
  def change
    add_column :transactions, :sales_tax_cents, :integer, null: false, default: 0
    add_column :transactions, :processor_fee_cents, :integer, null: false, default: 0
    add_column :transactions, :sales_tax_period_starts_on, :date
    add_column :invoices, :sales_tax_cents, :integer, null: false, default: 0
    add_column :invoice_payments, :sales_tax_cents, :integer, null: false, default: 0
  end
end
