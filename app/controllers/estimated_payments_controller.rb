class EstimatedPaymentsController < ApplicationController
  include TaxYearParam

  household_page
  before_action :require_household_access!
  before_action :require_household_owner!
  before_action -> { @year = tax_year_from(params[:tax_year_year]) }
  before_action :set_payment, only: %i[edit update destroy]

  def new
    @payment = EstimatedPayment.new
    load_candidates
  end

  def create
    @payment = EstimatedPayment.new(tax_year: Household.instance.tax_years.find_or_initialize_by(year: @year))
    debit_id = params.dig(:estimated_payment, :debit_id)
    if debit_id.present?
      @payment.link(Tax::PaymentCandidates.scope_for(Current.user).find(debit_id))
    else
      @payment.assign_attributes(payment_params)
    end

    if @payment.save
      redirect_to tax_year_path(@year), notice: "Payment recorded."
    else
      load_candidates
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @payment.update(payment_params)
      redirect_to tax_year_path(@year), notice: "Payment updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @payment.destroy!
    redirect_to tax_year_path(@year), notice: "Payment deleted."
  end

  private

  def set_payment
    @payment = EstimatedPayment.joins(:tax_year).where(tax_years: { household_id: Household.instance.id, year: @year }).find(params[:id])
  end

  def payment_params = params.expect(estimated_payment: %i[paid_on amount quarter])

  def load_candidates
    @query = params[:q].to_s
    @candidates = Tax::PaymentCandidates.for(user: Current.user, year: @year, query: @query)
  end
end
