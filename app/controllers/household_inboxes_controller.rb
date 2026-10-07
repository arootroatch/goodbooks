class HouseholdInboxesController < ApplicationController
  def show
    businesses = Current.user.accessible_businesses.active.order(:name).to_a
    @memberships = Current.user.memberships.where(business: businesses).index_by(&:business_id)
    @categories = Category.active.where(business: businesses).order(:name).group_by(&:business_id)
    @groups = businesses.map do |business|
      scope = Transaction.for_businesses(business.id).inbox
      rows = scope.includes(:account).order(posted_on: :desc, id: :desc).limit(InboxesController::LIMIT).to_a
      [ business, rows, scope.count ]
    end
    @matcher = InvoiceMatcher.for_businesses(businesses.select(&:business?).map(&:id))
  end
end
