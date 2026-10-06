class ScheduleCsController < ApplicationController
  include BusinessScoped

  def show
    @year = (params[:year].presence || Date.current.year).to_i
    range = Date.new(@year).all_year
    @mileage = Reports::MileageTotals.load(business_ids: [@business.id], range: range)
    @summary = Reports::ScheduleCSummary.new(
      category_totals: Reports::CategoryTotals.load(business_ids: [@business.id], range: range),
      mileage_deduction_cents: @mileage.deduction_cents
    )
  end
end
