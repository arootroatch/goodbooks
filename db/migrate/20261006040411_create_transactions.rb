class CreateTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :transactions do |t|
      t.references :account, null: false, foreign_key: true
      t.date :posted_on, null: false
      t.integer :amount_cents, null: false
      t.string :payee, null: false
      t.string :memo
      t.references :category, foreign_key: true
      t.boolean :transfer, null: false, default: false
      t.boolean :excluded, null: false, default: false
      t.string :external_id
      t.string :categorized_by
      t.integer :rule_id
      t.timestamps
    end
    add_index :transactions, :posted_on
    add_index :transactions, :rule_id
    add_index :transactions, %i[account_id external_id], unique: true, where: "external_id IS NOT NULL"
  end
end
