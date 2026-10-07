class DashboardsController < ApplicationController
  def show
    @businesses = Current.user.accessible_businesses.business_kind.active.order(:name)
    @receivables = Invoice.receivables_by_business(@businesses.map(&:id))
    book = Current.user.accessible_businesses.personal.first
    @tithe = book && Tithe.ledger_for(book)
  end
end
