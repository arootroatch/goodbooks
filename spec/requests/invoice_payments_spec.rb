require "rails_helper"

RSpec.describe "Invoice payments" do
  let!(:business) { create(:business) }
  let!(:account) { create(:account, business: business, name: "Checking") }
  let!(:sales) { create(:category, :income, business: business, name: "Sales") }
  let!(:invoice) { create(:invoice, business: business, number: "INV-1042", amount_cents: 120_000) }
  let!(:exact) { create(:transaction, account: account, amount_cents: 120_000, payee: "ACME EXACT", posted_on: Date.current - 3) }
  let!(:recent) { create(:transaction, account: account, amount_cents: 50_000, payee: "ACME RECENT", posted_on: Date.current - 10) }
  let!(:old) { create(:transaction, account: account, amount_cents: 50_000, payee: "ACME OLD", posted_on: Date.current - 200) }

  it "explains a fully paid invoice instead of hiding it behind the new page" do
    sign_in_as user_with_role("editor", business)
    other = create(:transaction, account: account, amount_cents: 120_000, payee: "ACME TWO", posted_on: Date.current - 2)
    post business_invoice_payments_path(business, invoice), params: { deposit_id: exact.id }
    post business_invoice_payments_path(business, invoice), params: { deposit_id: other.id }
    expect(response).to redirect_to(business_invoice_path(business, invoice))
    expect(flash[:alert]).to eq("This invoice is already fully paid.")
  end

  it "rejects a blank amount instead of linking the full amount" do
    sign_in_as user_with_role("editor", business)
    expect {
      post business_invoice_payments_path(business, invoice), params: { deposit_id: exact.id, amount: " " }
    }.not_to change(InvoicePayment, :count)
    expect(flash[:alert]).to eq("Amount can't be blank.")
  end

  it "does not list deposits already linked to this invoice" do
    sign_in_as user_with_role("editor", business)
    create(:invoice_payment, invoice: invoice, deposit: recent, amount_cents: 10_000)
    get new_business_invoice_payment_path(business, invoice)
    expect(response.body).to include("ACME EXACT")
    expect(response.body).not_to include("ACME RECENT")
  end

  it "lists exact matches first, then recent deposits, with an older-date filter" do
    sign_in_as user_with_role("editor", business)
    get new_business_invoice_payment_path(business, invoice)
    expect(response.body).to include("ACME EXACT", "ACME RECENT")
    expect(response.body).not_to include("ACME OLD")
    expect(response.body.index("ACME EXACT")).to be < response.body.index("ACME RECENT")

    get new_business_invoice_payment_path(business, invoice, from: (Date.current - 365).iso8601)
    expect(response.body).to include("ACME OLD")
  end

  it "links a deposit and marks the invoice paid" do
    sign_in_as user_with_role("editor", business)
    post business_invoice_payments_path(business, invoice), params: { deposit_id: exact.id }
    expect(response).to redirect_to(business_invoice_path(business, invoice))
    expect(flash[:notice]).to eq("Payment recorded.")
    expect(invoice.reload).to be_paid
  end

  it "records a typed partial amount and rejects amounts that don't parse" do
    sign_in_as user_with_role("editor", business)
    post business_invoice_payments_path(business, invoice), params: { deposit_id: exact.id, amount: "abc" }
    expect(flash[:alert]).to eq("Amount is not a valid amount.")
    post business_invoice_payments_path(business, invoice), params: { deposit_id: exact.id, amount: "0" }
    expect(flash[:alert]).to eq("Amount must be greater than zero.")
    post business_invoice_payments_path(business, invoice), params: { deposit_id: exact.id, amount: "$200.00" }
    expect(invoice.reload.paid_cents).to eq(20_000)
  end

  it "rejects a double submit" do
    sign_in_as user_with_role("editor", business)
    post business_invoice_payments_path(business, invoice), params: { deposit_id: recent.id }
    post business_invoice_payments_path(business, invoice), params: { deposit_id: recent.id }
    expect(flash[:alert]).to eq("That deposit is already linked to this invoice.")
    expect(InvoicePayment.count).to eq(1)
  end

  it "unlinks a payment" do
    payment = InvoicePayments.link(invoice: invoice, deposit: exact).payment
    sign_in_as user_with_role("editor", business)
    delete business_invoice_payment_path(business, invoice, payment)
    expect(response).to redirect_to(business_invoice_path(business, invoice))
    expect(invoice.reload).to be_sent
  end

  it "won't open the page for drafts" do
    invoice.update!(status: "draft")
    sign_in_as user_with_role("editor", business)
    get new_business_invoice_payment_path(business, invoice)
    expect(response).to redirect_to(business_invoice_path(business, invoice))
    expect(flash[:alert]).to eq("Only sent invoices with a balance can take payments.")
  end

  it "404s for another business's deposit or category" do
    sign_in_as user_with_role("editor", business)
    post business_invoice_payments_path(business, invoice), params: { deposit_id: create(:transaction, amount_cents: 120_000).id }
    expect(response).to have_http_status(:not_found)
    post business_invoice_payments_path(business, invoice), params: { deposit_id: exact.id, category_id: create(:category, :income).id }
    expect(response).to have_http_status(:not_found)
    expect(InvoicePayment.count).to eq(0)
  end

  it "forbids viewers and 404s non-members" do
    payment = InvoicePayments.link(invoice: invoice, deposit: recent).payment
    sign_in_as user_with_role("viewer", business)
    get new_business_invoice_payment_path(business, invoice)
    expect(response).to have_http_status(:forbidden)
    post business_invoice_payments_path(business, invoice), params: { deposit_id: exact.id }
    expect(response).to have_http_status(:forbidden)
    delete business_invoice_payment_path(business, invoice, payment)
    expect(response).to have_http_status(:forbidden)
    expect(InvoicePayment.count).to eq(1)

    sign_in_as create(:user)
    get new_business_invoice_payment_path(business, invoice)
    expect(response).to have_http_status(:not_found)
  end
end
