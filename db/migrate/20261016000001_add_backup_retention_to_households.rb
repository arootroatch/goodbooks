class AddBackupRetentionToHouseholds < ActiveRecord::Migration[8.1]
  def change
    add_column :households, :backup_retention, :integer, null: false, default: 14
  end
end
