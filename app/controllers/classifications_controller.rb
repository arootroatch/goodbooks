class ClassificationsController < ApplicationController
  include BusinessScoped

  before_action :require_editor!

  def update
    @transaction = Transaction.for_businesses(@business.id).find(params[:transaction_id])
    attrs = classification_attributes
    return redirect_back_or_to(business_inbox_path(@business), alert: "Choose a category.") unless attrs

    @transaction.update!(attrs.merge(categorized_by: "user"))

    if params[:make_rule] == "1" && @transaction.category
      redirect_to new_business_rule_path(@business, value: @transaction.payee.squish.split.first, category_id: @transaction.category_id)
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.remove(@transaction) }
        format.html { redirect_back_or_to business_inbox_path(@business) }
      end
    end
  end

  private

  def classification_attributes
    case params[:outcome]
    when "transfer" then { transfer: true, excluded: false }
    when "exclude" then { excluded: true }
    else
      category = @business.categories.find_by(id: params[:category_id])
      category && { category: category, transfer: false }
    end
  end
end
