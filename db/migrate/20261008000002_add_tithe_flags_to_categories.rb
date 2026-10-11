class AddTitheFlagsToCategories < ActiveRecord::Migration[8.1]
  def change
    change_column_null :categories, :schedule_c_line, true
    add_column :categories, :tithable, :boolean, null: false, default: true
    add_column :categories, :tithe, :boolean, null: false, default: false
  end
end
