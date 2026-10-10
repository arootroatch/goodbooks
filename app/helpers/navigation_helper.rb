module NavigationHelper
  def nav_link(name, path, badge: nil)
    link_to path, aria: { current: ("page" if current_page?(path)) } do
      safe_join([ name, (tag.span(badge, class: "badge") if badge&.positive?) ].compact, " ")
    end
  end

  def settings_links(user = Current.user)
    [
      (nav_link "Tax parameters", tax_parameters_path if user.household_owner?),
      (nav_link "Invites", invites_path if user.household_owner? || user.memberships.owner.exists?),
      (nav_link "People", people_path if user.household_owner?)
    ].compact
  end

  def business_inbox_count(business) = Transaction.for_businesses(business.id).inbox.count
end
