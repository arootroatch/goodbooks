require "rails_helper"

RSpec.describe "Inbox invoice hint" do
  let!(:business) { create(:business) }
  let!(:account) { create(:account, business: business) }
  let!(:sales) { create(:category, :income, business: business, name: "Sales") }
  let!(:client) { create(:client, business: business, name: "Acme") }
  let!(:invoice) { create(:invoice, business: business, client: client, number: "INV-1042", amount_cents: 120_000, due_date: Date.new(2026, 9, 30)) }
  let!(:deposit) { create(:transaction, account: account, amount_cents: 120_000, payee: "ACME CORP") }
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }

  it "shows editors the hint on a matching row" do
    sign_in_as user_with_role("editor", business)
    get business_inbox_path(business)
    expect(response.body).to include("Matches", "INV-1042", "Acme", "due Sep 30", "Mark paid")
  end

  it "shows the hint in the household inbox" do
    sign_in_as user_with_role("editor", business)
    get household_inbox_path
    expect(response.body).to include("INV-1042", "Mark paid")
  end

  it "hides the hint from viewers and on rows that don't match" do
    deposit.update!(amount_cents: 119_999)
    sign_in_as user_with_role("editor", business)
    get business_inbox_path(business)
    expect(response.body).not_to include("Mark paid")

    deposit.update!(amount_cents: 120_000)
    sign_in_as user_with_role("viewer", business)
    get business_inbox_path(business)
    expect(response.body).not_to include("Mark paid")
  end

  it "offers a category choice when there are several gross-receipts categories, and a link when there are none" do
    create(:category, :income, business: business, name: "Retail sales")
    sign_in_as user_with_role("editor", business)
    get business_inbox_path(business)
    expect(response.body).to include("Retail sales")

    business.categories.income.update_all(schedule_c_line: "6")
    get business_inbox_path(business)
    expect(response.body).not_to include("Mark paid")
    expect(response.body).to include(new_business_invoice_payment_path(business, invoice))
  end

  it "offers only the taxable category for a taxed invoice and marks paid into it" do
    create(:sales_tax_profile, business: business)
    sales.update!(sales_tax_treatment: "taxable")
    create(:category, :income, business: business, name: "Consulting", sales_tax_treatment: "exempt")
    invoice.update!(amount_cents: 109_250, sales_tax_cents: 9_250)
    deposit.update!(amount_cents: 109_250)
    sign_in_as user_with_role("editor", business)

    get business_inbox_path(business)
    hint = Nokogiri::HTML(response.body).at_css(".invoice-hint").to_html
    expect(hint).to include("Mark paid")
    expect(hint).not_to include("Consulting")
    expect(hint).to include(%(name="category_id"), %(value="#{sales.id}"))

    post business_invoice_payments_path(business, invoice), params: { deposit_id: deposit.id, category_id: sales.id, from_inbox: "1" }, headers: turbo
    expect(invoice.reload).to be_paid
    expect(deposit.reload.category).to eq(sales)
  end

  it "marks paid with a turbo stream that removes the row" do
    sign_in_as user_with_role("editor", business)
    post business_invoice_payments_path(business, invoice), params: { deposit_id: deposit.id, category_id: sales.id, from_inbox: "1" }, headers: turbo
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include(%(action="remove" target="transaction_#{deposit.id}"))
    expect(invoice.reload).to be_paid
    expect(deposit.reload.category).to eq(sales)
  end

  it "replaces the row with the error when the invoice was paid meanwhile (double submit)" do
    sign_in_as user_with_role("editor", business)
    post business_invoice_payments_path(business, invoice), params: { deposit_id: deposit.id, category_id: sales.id, from_inbox: "1" }, headers: turbo
    other = create(:transaction, account: account, amount_cents: 120_000)
    post business_invoice_payments_path(business, invoice), params: { deposit_id: other.id, category_id: sales.id, from_inbox: "1" }, headers: turbo
    expect(response.body).to include(%(action="replace" target="transaction_#{other.id}"))
    expect(response.body).to include("This invoice is already fully paid.")
    expect(InvoicePayment.count).to eq(1)
  end

  it "falls back to a redirect for HTML" do
    sign_in_as user_with_role("editor", business)
    post business_invoice_payments_path(business, invoice), params: { deposit_id: deposit.id, category_id: sales.id, from_inbox: "1" }
    expect(response).to redirect_to(business_inbox_path(business))
    expect(flash[:notice]).to eq("Payment recorded.")
  end
end
