# Resolves a row Plaid removed or changed after the user had worked on it: keep it as is, or exclude it.
class TransactionReviewsController < ApplicationController
  include BusinessScoped

  DECISIONS = {
    "keep" => { review_reason: nil },
    "exclude" => { review_reason: nil, excluded: true }
  }.freeze

  before_action :require_editor!

  def update
    txn = Transaction.for_businesses(@business.id).needs_review.find(params[:transaction_id])
    attrs = DECISIONS[params[:decision]]
    return head :unprocessable_content unless attrs

    unless txn.update(attrs)
      return redirect_back_or_to business_inbox_path(@business), alert: txn.errors.full_messages.to_sentence
    end

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(helpers.dom_id(txn, :review)) }
      format.html { redirect_back_or_to business_inbox_path(@business) }
    end
  end
end
