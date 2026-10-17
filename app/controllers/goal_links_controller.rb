# Unlinks one transaction from a payment goal. The row keeps goal_linked_by "user" so the matcher leaves it alone.
class GoalLinksController < ApplicationController
  include BusinessScoped

  before_action :require_editor!

  def destroy
    goal = @business.goals.find(params[:goal_id])
    txn = goal.transactions.find(params[:id])
    txn.update_columns(goal_id: nil, goal_linked_by: "user", updated_at: Time.current)
    Audit.note("Unlinked from goal #{goal.name}", record: txn)
    redirect_to business_goal_path(@business, goal), notice: "Transaction unlinked.", status: :see_other
  end
end
