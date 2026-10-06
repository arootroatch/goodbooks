class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts do |t|
      t.references :business, null: false, foreign_key: true
      t.string :name, null: false
      t.string :source, null: false
      t.string :kind, null: false
      t.json :csv_mapping
      t.datetime :archived_at
      t.timestamps
    end
  end
end
