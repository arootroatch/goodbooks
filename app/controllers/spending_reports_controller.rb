class SpendingReportsController < ApplicationController
  include BusinessScoped
  include PersonalOnly
  include DateRangeParams

  def show
    @report = Reports::Spending.new(Reports::Spending.load(business_id: @business.id, range: date_range),
                                    months: Reports::Spending.months_in(date_range))
    respond_to do |format|
      format.html { @uncategorized_count = Transaction.for_businesses(@business.id).inbox.where(posted_on: date_range).count }
      format.csv do
        send_data Reports::SpendingCsv.generate(@report), filename: "spending-#{date_range.first}-#{date_range.last}.csv", type: "text/csv"
      end
    end
  end

  private

  # Overrides DateRangeParams#date_range (also the date form's helper) so a typo can't build thousands of month columns.
  def date_range
    @date_range ||= clamp_range(super)
  end

  def clamp_range(range)
    from = [ range.first, Business::TITHE_START_FLOOR ].max
    to = [ range.last, Date.current ].min
    from = to if from > to
    if from != range.first || to != range.last
      flash.now[:notice] = "Showing #{from} to #{to}; the report covers #{Business::TITHE_START_FLOOR} through today."
    end
    from..to
  end
end
