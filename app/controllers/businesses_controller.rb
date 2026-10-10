class BusinessesController < ApplicationController
  include BusinessScoped
  include DateRangeParams

  before_action :require_household_owner!, only: %i[new create]
  skip_before_action :set_business, only: %i[new create]
  before_action :require_owner!, only: %i[edit update]

  def new
    @business = Household.instance.businesses.new
  end

  def create
    @business = Household.instance.businesses.new(params.expect(business: %i[name person_id]))
    if @business.valid?
      BusinessProvisioner.call(@business, owner: Current.user)
      redirect_to business_path(@business), notice: "Business created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def show
    ids = [ @business.id ]
    @report = Reports::ProfitAndLoss.new(
      category_totals: Reports::CategoryTotals.load(business_ids: ids, range: date_range),
      mileage_deduction_cents: Reports::MileageTotals.load(business_ids: ids, range: date_range).deduction_cents
    )
    @top_expenses = @report.expense_lines.select { _1.actual_cents.positive? }.sort_by { -_1.actual_cents }.first(5)
    @months = Reports::MonthlyTotals.load(business_ids: ids, year: date_range.last.year, through_month: date_range.last.month)
    inbox = Transaction.for_businesses(@business.id).inbox
    @inbox_count = inbox.count
    @inbox_preview = inbox.order(:posted_on, :id).limit(3)
    @accounts = @business.accounts.active.order(:name)
  end

  def edit
  end

  def update
    if @business.update(params.expect(business: %i[name]))
      redirect_to business_path(@business), notice: "Business updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def business_id_param
    params[:id]
  end
end
