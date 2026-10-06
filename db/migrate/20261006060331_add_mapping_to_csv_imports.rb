class AddMappingToCsvImports < ActiveRecord::Migration[8.1]
  def change
    add_column :csv_imports, :mapping, :json
  end
end
