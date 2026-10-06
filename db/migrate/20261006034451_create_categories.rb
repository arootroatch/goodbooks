class CreateCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :categories do |t|
      t.references :business, null: false, foreign_key: true
      t.string :name, null: false
      t.string :kind, null: false
      t.string :schedule_c_line, null: false
      t.integer :deductible_bps, null: false, default: 10_000
      t.datetime :archived_at
      t.timestamps
    end
    add_index :categories, %i[business_id name], unique: true
  end
end
