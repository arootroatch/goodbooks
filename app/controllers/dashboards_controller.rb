class DashboardsController < ApplicationController
  household_page

  def show
    @dashboard = HouseholdDashboard.new(user: Current.user)
  end
end
