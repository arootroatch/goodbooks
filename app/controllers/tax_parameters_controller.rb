class TaxParametersController < ApplicationController
  FEDERAL_FIELDS = %i[
    standard_deduction_mfj ss_wage_base additional_medicare_threshold_mfj qbi_threshold_mfj home_office_simplified_rate
    safe_harbor_high_agi_threshold annual_additions_limit elective_deferral_limit se_earnings_percent ss_rate_percent
    medicare_rate_percent additional_medicare_percent qbi_percent home_office_simplified_max_sqft
  ].freeze

  before_action :require_household_owner!
  before_action :set_tax_parameters, only: %i[edit update]

  def index
    @all = TaxParameters.order(year: :desc)
  end

  def new
    @tax_parameters = TaxParameters.new(year: year_param)
    @tax_parameters.assign_attributes(TaxParameters::Published::YEARS.fetch(year_param, {}))
  end

  def create
    @tax_parameters = TaxParameters.new(create_params)
    if @tax_parameters.save
      redirect_to tax_parameters_path, notice: "Saved."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @tax_parameters.update(update_params)
      redirect_to tax_parameters_path, notice: "Saved."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def create_params = params.expect(tax_parameter: [ :year, :mileage_rate_cents, *FEDERAL_FIELDS, bracket_rows: [ [ :floor, :rate ] ] ])
  def update_params = params.expect(tax_parameter: [ :mileage_rate_cents, *FEDERAL_FIELDS, bracket_rows: [ [ :floor, :rate ] ] ])

  def set_tax_parameters
    @tax_parameters = TaxParameters.find(params[:id])
  end
end
