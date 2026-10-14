class AddGoalToTransactions < ActiveRecord::Migration[8.1]
  def change
    add_reference :transactions, :goal, foreign_key: true
    add_column :transactions, :goal_linked_by, :string
  end
end
