class InboxesController < ApplicationController
  include BusinessScoped

  def show
    @transactions = Transaction.for_businesses(@business.id).inbox.includes(:account).order(posted_on: :desc, id: :desc)
    @categories = @business.categories.active.order(:name)
  end
end
