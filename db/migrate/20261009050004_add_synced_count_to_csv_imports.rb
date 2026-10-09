class AddSyncedCountToCsvImports < ActiveRecord::Migration[8.1]
  def change
    add_column :csv_imports, :synced_count, :integer, null: false, default: 0
  end
end
