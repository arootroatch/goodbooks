class DashboardsController < ApplicationController
  household_page

  def show
    @dashboard = HouseholdDashboard.new(user: Current.user)
    @review_counts = Transaction.for_businesses(Current.user.accessible_businesses.active.select(:id)).needs_review
      .group("accounts.business_id").count
    @review_books = Current.user.accessible_businesses.active.where(id: @review_counts.keys).order(:name)
    @reconnect_items = PlaidItem.needing_reconnect_for(Current.user).to_a
    @tax_estimate = Tax.estimate(household: Household.instance, year: Date.current.year) if Current.user.can_view_household?
  end
end
