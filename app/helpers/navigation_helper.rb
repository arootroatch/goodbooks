module NavigationHelper
  def nav_link(name, path, badge: nil)
    link_to path, aria: { current: ("page" if current_page?(path)) } do
      safe_join([ name, (tag.span(badge, class: "badge") if badge&.positive?) ].compact, " ")
    end
  end

  SettingsEntry = Data.define(:name, :path, :badge)

  def settings_entries(user = Current.user)
    [
      (SettingsEntry.new("Household", edit_household_path, nil) if user.household_owner?),
      (SettingsEntry.new("Tax parameters", tax_parameters_path, nil) if user.household_owner?),
      (SettingsEntry.new("Invites", invites_path, nil) if user.household_owner? || user.memberships.owner.exists?),
      (SettingsEntry.new("Users", users_path, nil) if user.household_owner?),
      (SettingsEntry.new("Banks", plaid_items_path, nil) if show_bank_connections?),
      (SettingsEntry.new("People", people_path, nil) if user.household_owner?),
      (SettingsEntry.new("Audit log", audit_events_path, nil) if user.household_owner?),
      (SettingsEntry.new("Backups", backups_path, nil) if user.household_owner?),
      (SettingsEntry.new("Errors", error_events_path, ErrorEvent.unresolved.count) if user.household_owner?)
    ].compact
  end

  # Collapsed unless the user opened it (remembered in a cookie) or is on one of its pages.
  def settings_open?(entries)
    cookies[:settings_nav] == "open" || entries.any? { current_page?(_1.path) }
  end

  def business_inbox_count(business) = Transaction.for_businesses(business.id).inbox.count
end
