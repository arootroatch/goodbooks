class DashboardsController < ApplicationController
  household_page

  def show
    @dashboard = HouseholdDashboard.new(user: Current.user)
    @reconnect_items = PlaidItem.needing_reconnect_for(Current.user).to_a
  end
end
