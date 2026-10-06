class TaxParametersController < ApplicationController
  before_action :require_household_owner!
  before_action :set_tax_parameters, only: %i[edit update]

  def index
    @all = TaxParameters.order(year: :desc)
  end

  def new
    @tax_parameters = TaxParameters.new(year: year_param)
  end

  def create
    @tax_parameters = TaxParameters.new(params.expect(tax_parameter: %i[year mileage_rate_cents]))
    if @tax_parameters.save
      redirect_to tax_parameters_path, notice: "Saved."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @tax_parameters.update(params.expect(tax_parameter: %i[mileage_rate_cents]))
      redirect_to tax_parameters_path, notice: "Saved."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_tax_parameters
    @tax_parameters = TaxParameters.find(params[:id])
  end
end
