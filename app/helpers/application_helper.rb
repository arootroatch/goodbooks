module ApplicationHelper
  def money(cents)
    cents.nil? ? "—" : Money.new(cents).to_s
  end

  def current_personal_book
    return @current_personal_book if defined?(@current_personal_book)

    @current_personal_book = Current.user.accessible_businesses.personal.first
  end

  def business_nav(business)
    render "businesses/nav", business: business
  end
end
