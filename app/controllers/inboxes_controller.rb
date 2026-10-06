class InboxesController < ApplicationController
  include BusinessScoped

  LIMIT = 200

  def show
    scope = Transaction.for_businesses(@business.id).inbox
    @total = scope.count
    @transactions = scope.includes(:account).order(posted_on: :desc, id: :desc).limit(LIMIT).to_a
    @categories = @business.categories.active.order(:name)
  end
end
