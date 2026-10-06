class CreateCsvImports < ActiveRecord::Migration[8.1]
  def change
    create_table :csv_imports do |t|
      t.references :account, null: false, foreign_key: true
      t.string :status, null: false, default: "previewed"
      t.integer :row_count, null: false, default: 0
      t.integer :new_count, null: false, default: 0
      t.integer :duplicate_count, null: false, default: 0
      t.integer :error_count, null: false, default: 0
      t.datetime :committed_at
      t.timestamps
    end
  end
end
