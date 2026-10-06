class DashboardsController < ApplicationController
  def show
    @businesses = Current.user.accessible_businesses.active.order(:name)
  end
end
