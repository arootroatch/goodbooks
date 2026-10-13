class TaxYearsController < ApplicationController
  include TaxYearParam

  household_page
  before_action :require_household_access!
  before_action :require_household_owner!, only: %i[edit update]
  before_action -> { @year = tax_year_from(params[:year]) }, except: :index

  def index
    redirect_to tax_year_path(Tax.current_year)
  end

  def show
    @household = Household.instance
    @parameters = TaxParameters.for_year(@year)
    quarter = params[:quarter].to_i
    @estimate = Tax.estimate(household: @household, year: @year, quarter: (1..4).cover?(quarter) ? quarter : nil)
    @payments = @household.tax_years.find_by(year: @year)&.estimated_payments&.includes(debit: :account)&.order(:paid_on, :id).to_a || []
    @visible_book_ids = Current.user.accessible_businesses.ids
    @uncategorized_count = Transaction.for_businesses(Business.business_kind.select(:id)).inbox.where(posted_on: Date.new(@year).all_year).count
    @businesses = Business.business_kind.order(:name) if @estimate.nil?
    @people = @household.people.order(:name) if @estimate.nil?
  end

  def edit
    @tax_year = Household.instance.tax_years.find_or_initialize_by(year: @year)
  end

  def update
    @tax_year = Household.instance.tax_years.find_or_initialize_by(year: @year)
    if @tax_year.update(params.expect(tax_year: %i[prior_year_total_tax prior_year_agi]))
      redirect_to tax_year_path(@year), notice: "Prior-year figures saved."
    else
      render :edit, status: :unprocessable_content
    end
  end
end
