class SalesTaxFilingsController < ApplicationController
  include BusinessScoped
  include BusinessKindOnly
  include SalesTaxPeriodLookup

  before_action :require_editor!
  before_action :set_period

  def create
    filing = @business.sales_tax_filings.new(params.expect(sales_tax_filing: %i[filed_on confirmation_number]))
    filing.period_starts_on = @period.starts_on
    if filing.save
      redirect_to period_path, notice: "Period marked filed."
    else
      redirect_to period_path, alert: filing.errors.full_messages.to_sentence
    end
  end

  def destroy
    @business.sales_tax_filings.find_by!(period_starts_on: @period.starts_on).destroy!
    redirect_to period_path, notice: "Filing removed.", status: :see_other
  end

  private

  def set_period
    @period = find_sales_tax_period(params[:sales_tax_period_starts_on])
  end

  def period_path = business_sales_tax_period_path(@business, @period.starts_on)
end
