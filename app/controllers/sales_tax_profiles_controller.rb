class SalesTaxProfilesController < ApplicationController
  include BusinessScoped
  include BusinessKindOnly

  PERMITTED = %i[tn_account_number filing_frequency default_rate_percent starts_on active].freeze

  before_action :require_owner!, only: :update

  def show
    @collects = @business.collects_sales_tax?
    @reports = @collects ? SalesTax.reports_for(@business).reverse : []
    @profile = @business.sales_tax_profile
    @profile ||= SalesTaxProfile.new(business: @business, filing_frequency: "quarterly", default_rate_bps: 925,
                                     starts_on: Date.current.beginning_of_quarter, active: true) if current_membership.owner?
  end

  def update
    @profile = @business.sales_tax_profile || SalesTaxProfile.new(business: @business)
    @profile.assign_attributes(params.expect(sales_tax_profile: PERMITTED))
    if @profile.save
      redirect_to business_sales_tax_profile_path(@business), notice: "Sales tax settings saved."
    else
      @collects = false
      @reports = []
      render :show, status: :unprocessable_content
    end
  end
end
