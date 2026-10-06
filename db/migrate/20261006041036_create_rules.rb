class CreateRules < ActiveRecord::Migration[8.1]
  def change
    create_table :rules do |t|
      t.references :business, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :field, null: false
      t.string :operator, null: false
      t.string :value, null: false
      t.integer :amount_min_cents
      t.integer :amount_max_cents
      t.string :outcome, null: false
      t.references :category, foreign_key: true
      t.timestamps
    end
    add_foreign_key :transactions, :rules, on_delete: :nullify
  end
end
