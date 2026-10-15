class CreateGoals < ActiveRecord::Migration[8.1]
  def change
    create_table :goals do |t|
      t.references :business, null: false, foreign_key: true
      t.references :account, foreign_key: true
      t.string :name, null: false
      t.string :kind, null: false
      t.integer :target_cents, null: false
      t.integer :position, null: false
      t.date :target_date
      t.datetime :archived_at
      t.string :match_field
      t.string :match_operator
      t.string :match_value
      t.integer :match_amount_min_cents
      t.integer :match_amount_max_cents
      t.timestamps
    end
  end
end
