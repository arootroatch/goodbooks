class HouseholdTransactionExportsController < ApplicationController
  include DateRangeParams

  before_action :require_household_access!

  def show
    transactions = Transaction.for_businesses(Business.business_kind.select(:id)).where(excluded: false, posted_on: date_range)
      .includes(:category, :invoice_payments, account: :business).order(:posted_on, :id)
    send_data Reports::TransactionCsv.generate(transactions),
      filename: "household-transactions-#{date_range.first}-#{date_range.last}.csv", type: "text/csv"
  end
end
