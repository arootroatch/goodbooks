class CreateInvoices < ActiveRecord::Migration[8.1]
  def change
    create_table :invoices do |t|
      t.references :business, null: false, foreign_key: true
      t.references :client, null: false, foreign_key: true
      t.string :number, null: false
      t.date :issue_date, null: false
      t.date :due_date, null: false
      t.integer :amount_cents, null: false
      t.text :description
      t.string :status, null: false, default: "sent"
      t.date :paid_on
      t.timestamps
    end
    add_index :invoices, %i[business_id number], unique: true
    add_index :invoices, %i[business_id status]
  end
end
