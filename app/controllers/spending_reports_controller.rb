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
end
