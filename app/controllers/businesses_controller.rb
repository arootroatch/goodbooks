class BusinessesController < ApplicationController
  include BusinessScoped

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
    @accounts = @business.accounts.active.order(:name)
    @receivables = Invoice.receivables_by_business([ @business.id ])[@business.id]
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
