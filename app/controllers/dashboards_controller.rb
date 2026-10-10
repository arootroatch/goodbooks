class DashboardsController < ApplicationController
  household_page

  def show
    @businesses = Current.user.accessible_businesses.active.order(:name)
  end
end
