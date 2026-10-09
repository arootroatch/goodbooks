module PlaidItemsHelper
  STATUS_LABELS = { "ok" => "Connected", "login_required" => "Needs reconnecting", "error" => "Error" }.freeze

  def plaid_status_label(item) = STATUS_LABELS.fetch(item.status)

  def book_label(business) = business.personal? ? "Personal" : business.name
end
