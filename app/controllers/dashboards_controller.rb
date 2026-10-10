class DashboardsController < ApplicationController
  household_page

  def show
    @businesses = Current.user.accessible_businesses.active.order(:name)
    @receivables = Invoice.receivables_by_business(@businesses.map(&:id))
  end
end
