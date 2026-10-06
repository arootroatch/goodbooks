class CreateInvoicePayments < ActiveRecord::Migration[8.1]
  def change
    create_table :invoice_payments do |t|
      t.references :invoice, null: false, foreign_key: true
      t.references :deposit, null: false, foreign_key: { to_table: :transactions }
      t.integer :amount_cents, null: false
      t.timestamps
    end
    add_index :invoice_payments, %i[invoice_id deposit_id], unique: true
  end
end
