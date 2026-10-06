class ProfitAndLossesController < ApplicationController
  include BusinessScoped
  include DateRangeParams

  def show
    @uncategorized_count = Transaction.for_businesses(@business.id).inbox.where(posted_on: date_range).count
    @mileage = Reports::MileageTotals.load(business_ids: [ @business.id ], range: date_range)
    @report = Reports::ProfitAndLoss.new(
      category_totals: Reports::CategoryTotals.load(business_ids: [ @business.id ], range: date_range),
      mileage_deduction_cents: @mileage.deduction_cents
    )
  end
end
