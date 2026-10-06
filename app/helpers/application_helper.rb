module ApplicationHelper
  def money(cents)
    cents.nil? ? "—" : Money.new(cents).to_s
  end

  def business_nav(business)
    render "businesses/nav", business: business
  end
end
