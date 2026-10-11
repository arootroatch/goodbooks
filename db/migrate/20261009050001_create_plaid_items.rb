class CreatePlaidItems < ActiveRecord::Migration[8.1]
  def change
    create_table :plaid_items do |t|
      t.references :household, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string :institution_name, null: false
      t.string :item_id, null: false
      t.text :access_token, null: false
      t.text :cursor
      t.string :status, null: false, default: "ok"
      t.datetime :last_synced_at
      t.string :last_error
      t.timestamps
    end
    add_index :plaid_items, :item_id, unique: true
  end
end
