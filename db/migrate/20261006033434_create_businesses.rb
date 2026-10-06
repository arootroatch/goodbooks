class CreateBusinesses < ActiveRecord::Migration[8.1]
  def change
    create_table :businesses do |t|
      t.references :household, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.string :name, null: false
      t.datetime :archived_at
      t.timestamps
    end
  end
end
