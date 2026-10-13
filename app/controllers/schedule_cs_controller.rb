class ScheduleCsController < ApplicationController
  include BusinessScoped
  include BusinessKindOnly

  def show
    @year = year_param
    range = Date.new(@year).all_year
    @uncategorized_count = Transaction.for_businesses(@business.id).inbox.where(posted_on: range).count
    @mileage = Reports::MileageTotals.load(business_ids: [ @business.id ], range: range)
    @home_office = @business.home_offices.find_by(year: @year)
    @can_edit_home_office = Current.user.can_edit_home_office?(@business)
    @summary = Reports::ScheduleCSummary.new(
      category_totals: Reports::CategoryTotals.load(business_ids: [ @business.id ], range: range),
      mileage_deduction_cents: @mileage.deduction_cents,
      home_office_cents: @home_office&.deduction_cents(TaxParameters.for_year(@year))
    )
  end
end
