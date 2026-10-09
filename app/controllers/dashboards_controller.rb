class DashboardsController < ApplicationController
  def show
    @businesses = Current.user.accessible_businesses.business_kind.active.order(:name)
    @receivables = Invoice.receivables_by_business(@businesses.map(&:id))
    book = Current.user.accessible_businesses.personal.first
    @tithe = book && Tithe.ledger_for(book)
    @reconnect_items = PlaidItem.needing_reconnect_for(Current.user).to_a
  end
end
