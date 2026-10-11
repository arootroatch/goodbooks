class AddPersonalBookToBusinesses < ActiveRecord::Migration[8.1]
  def change
    add_column :businesses, :kind, :string, null: false, default: "business"
    add_column :businesses, :tithe_start_on, :date
    change_column_null :businesses, :person_id, true
    add_index :businesses, :household_id, unique: true, where: "kind = 'personal'", name: "index_businesses_one_personal_per_household"
  end
end
