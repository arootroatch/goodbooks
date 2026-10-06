class TransactionExportsController < ApplicationController
  include BusinessScoped
  include DateRangeParams

  def show
    transactions = Transaction.for_businesses(@business.id).where(excluded: false, posted_on: date_range)
      .includes(:category, account: :business).order(:posted_on, :id)
    send_data Reports::TransactionCsv.generate(transactions),
      filename: "#{@business.name.parameterize}-transactions-#{date_range.first}-#{date_range.last}.csv", type: "text/csv"
  end
end
