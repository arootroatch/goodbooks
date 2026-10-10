module NavigationHelper
  def nav_link(name, path, badge: nil)
    link_to path, aria: { current: ("page" if current_page?(path)) } do
      safe_join([ name, (tag.span(badge, class: "badge") if badge&.positive?) ].compact, " ")
    end
  end

  def business_inbox_count(business) = Transaction.for_businesses(business.id).inbox.count
end
