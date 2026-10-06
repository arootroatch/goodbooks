class CreatePeople < ActiveRecord::Migration[8.1]
  def change
    create_table :people do |t|
      t.references :household, null: false, foreign_key: true
      t.references :user, foreign_key: true, index: { unique: true }
      t.string :name, null: false
      t.timestamps
    end
  end
end
