class AddSingletonGuardToHouseholds < ActiveRecord::Migration[8.1]
  def change
    add_column :households, :singleton, :boolean, null: false, default: true
    add_index :households, :singleton, unique: true
  end
end
