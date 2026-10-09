class DashboardsController < ApplicationController
  def show
    @businesses = Current.user.accessible_businesses.business_kind.active.order(:name)
    @receivables = Invoice.receivables_by_business(@businesses.map(&:id))
    book = Current.user.accessible_businesses.personal.first
    @tithe = book && Tithe.ledger_for(book)
    @review_counts = Transaction.for_businesses(Current.user.accessible_businesses.select(:id)).needs_review
      .group("accounts.business_id").count
    @review_books = Current.user.accessible_businesses.where(id: @review_counts.keys).order(:name)
    @reconnect_items = PlaidItem.needing_reconnect_for(Current.user).to_a
  end
end
