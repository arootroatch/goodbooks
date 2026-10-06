class HouseholdProfitAndLossesController < ApplicationController
  include DateRangeParams

  before_action :require_household_access!

  def show
    @report = Reports::HouseholdProfitAndLoss.new(
      Business.active.order(:name).to_h do |business|
        mileage = Reports::MileageTotals.load(business_ids: [business.id], range: date_range)
        [business, Reports::ProfitAndLoss.new(
          category_totals: Reports::CategoryTotals.load(business_ids: [business.id], range: date_range),
          mileage_deduction_cents: mileage.deduction_cents
        )]
      end
    )
  end
end
