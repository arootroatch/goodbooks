class DashboardsController < ApplicationController
  def show
    @businesses = Current.user.accessible_businesses.business_kind.active.includes(:sales_tax_profile).order(:name)
    @sales_tax = @businesses.index_with { SalesTax.summary_for(_1) }.compact
    @receivables = Invoice.receivables_by_business(@businesses.map(&:id))
    book = Current.user.accessible_businesses.personal.first
    @tithe = book && Tithe.ledger_for(book)
  end
end
