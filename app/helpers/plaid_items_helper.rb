module PlaidItemsHelper
  STATUS_LABELS = { "ok" => "Connected", "login_required" => "Needs reconnecting", "error" => "Error" }.freeze

  STATUS_BADGES = { "ok" => "badge-pos", "login_required" => "badge-neg", "error" => "badge-neg" }.freeze

  def plaid_status_label(item) = STATUS_LABELS.fetch(item.status)
  def plaid_status_badge(item) = tag.span(plaid_status_label(item), class: [ "badge", STATUS_BADGES.fetch(item.status) ])

  def book_label(business) = business.personal? ? "Personal" : business.name
end
