class ScheduleCsController < ApplicationController
  include BusinessScoped
  include BusinessKindOnly

  def show
    @year = year_param
    range = Date.new(@year).all_year
    @uncategorized_count = Transaction.for_businesses(@business.id).inbox.where(posted_on: range).count
    @mileage = Reports::MileageTotals.load(business_ids: [ @business.id ], range: range)
    @summary = Reports::ScheduleCSummary.new(
      category_totals: Reports::CategoryTotals.load(business_ids: [ @business.id ], range: range),
      mileage_deduction_cents: @mileage.deduction_cents
    )
  end
end
