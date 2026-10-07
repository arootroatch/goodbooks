class HouseholdProfitAndLossesController < ApplicationController
  include DateRangeParams

  before_action :require_household_access!

  def show
    businesses = Business.business_kind.order(:name).to_a
    mileage = businesses.index_with { |business| Reports::MileageTotals.load(business_ids: [ business.id ], range: date_range) }
    @missing_rate_years = mileage.values.flat_map(&:missing_rate_years).uniq.sort
    @uncategorized_count = Transaction.for_businesses(businesses.map(&:id)).inbox.where(posted_on: date_range).count
    @report = Reports::HouseholdProfitAndLoss.new(
      businesses.to_h do |business|
        [ business, Reports::ProfitAndLoss.new(
          category_totals: Reports::CategoryTotals.load(business_ids: [ business.id ], range: date_range),
          mileage_deduction_cents: mileage.fetch(business).deduction_cents
        ) ]
      end
    )
  end
end
