module ApplicationHelper
  def money(cents)
    return "—" if cents.nil?
    return Money.new(cents).to_s unless cents.negative?

    tag.span("(#{Money.new(-cents)})", class: "neg")
  end

  def business_nav(business)
    render "businesses/nav", business: business
  end
end
