require "rails_helper"

RSpec.describe "Invoices" do
  let!(:business) { create(:business) }
  let!(:client) { create(:client, business: business, name: "Acme") }
  let!(:invoice) { create(:invoice, business: business, client: client, number: "INV-0042", amount_cents: 120_000) }
  let(:valid) { { client_id: client.id.to_s, number: "INV-0043", issue_date: "2026-10-01", due_date: "2026-10-31", amount: "$1,500.00" } }

  describe "reading" do
    it "lists and shows invoices to viewers" do
      sign_in_as user_with_role("viewer", business)
      get business_invoices_path(business)
      expect(response.body).to include("INV-0042", "Acme", "$1,200.00")
      get business_invoice_path(business, invoice)
      expect(response).to have_http_status(:ok)
    end

    it "404s for non-members and for another business's invoice" do
      sign_in_as create(:user)
      get business_invoices_path(business)
      expect(response).to have_http_status(:not_found)

      sign_in_as user_with_role("owner", business)
      get business_invoice_path(business, create(:invoice))
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "writing" do
    it "forbids viewers from every write" do
      sign_in_as user_with_role("viewer", business)
      get new_business_invoice_path(business)
      expect(response).to have_http_status(:forbidden)
      post business_invoices_path(business), params: { invoice: valid }
      expect(response).to have_http_status(:forbidden)
      patch business_invoice_path(business, invoice), params: { invoice: { number: "X" } }
      expect(response).to have_http_status(:forbidden)
      %i[mark_sent void reopen].each do |action|
        patch send("#{action}_business_invoice_path", business, invoice)
        expect(response).to have_http_status(:forbidden)
      end
      delete business_invoice_path(business, invoice)
      expect(response).to have_http_status(:forbidden)
      expect(invoice.reload).to be_sent
    end

    it "prefills the next number and dates" do
      sign_in_as user_with_role("editor", business)
      get new_business_invoice_path(business)
      expect(response.body).to include('value="INV-0043"')
    end

    it "creates a sent invoice by default, or a draft" do
      sign_in_as user_with_role("editor", business)
      post business_invoices_path(business), params: { invoice: valid }
      created = business.invoices.find_by!(number: "INV-0043")
      expect(response).to redirect_to(business_invoice_path(business, created))
      expect(created).to be_sent
      expect(created.amount_cents).to eq(150_000)

      post business_invoices_path(business), params: { invoice: valid.merge(number: "INV-0044", status: "draft") }
      expect(business.invoices.find_by!(number: "INV-0044")).to be_draft
    end

    it "never takes a paid status from the form" do
      sign_in_as user_with_role("editor", business)
      post business_invoices_path(business), params: { invoice: valid.merge(status: "paid") }
      expect(business.invoices.find_by!(number: "INV-0043")).to be_sent
    end

    it "creates a new client inline" do
      sign_in_as user_with_role("editor", business)
      post business_invoices_path(business), params: { invoice: valid.merge(client_id: "new", new_client_name: "Globex") }
      expect(business.invoices.find_by!(number: "INV-0043").client.name).to eq("Globex")
    end

    it "keeps no orphan client when the invoice is invalid" do
      sign_in_as user_with_role("editor", business)
      expect {
        post business_invoices_path(business), params: { invoice: valid.merge(client_id: "new", new_client_name: "Globex", amount: "abc") }
      }.not_to change(Client, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "404s for a client from another business" do
      sign_in_as user_with_role("editor", business)
      post business_invoices_path(business), params: { invoice: valid.merge(client_id: create(:client).id.to_s) }
      expect(response).to have_http_status(:not_found)
    end

    it "re-renders typed amounts that don't parse" do
      sign_in_as user_with_role("editor", business)
      %w[abc 0 -5].each do |amount|
        post business_invoices_path(business), params: { invoice: valid.merge(amount: amount) }
        expect(response).to have_http_status(:unprocessable_content), "accepted #{amount}"
      end
    end

    it "updates an invoice" do
      sign_in_as user_with_role("editor", business)
      patch business_invoice_path(business, invoice), params: { invoice: { description: "October retainer" } }
      expect(response).to redirect_to(business_invoice_path(business, invoice))
      expect(invoice.reload.description).to eq("October retainer")
    end

    it "reverts a paid invoice to sent when its amount is raised" do
      create(:invoice_payment, invoice: invoice)
      invoice.sync_payment_status!
      sign_in_as user_with_role("editor", business)
      patch business_invoice_path(business, invoice), params: { invoice: { amount: "1,500.00" } }
      expect(invoice.reload).to be_sent
      expect(invoice.outstanding_cents).to eq(30_000)
    end

    it "marks drafts sent, voids, and reopens" do
      draft = create(:invoice, business: business, status: "draft")
      sign_in_as user_with_role("editor", business)
      patch mark_sent_business_invoice_path(business, draft)
      expect(draft.reload).to be_sent
      patch void_business_invoice_path(business, draft)
      expect(draft.reload).to be_void
      patch reopen_business_invoice_path(business, draft)
      expect(draft.reload).to be_sent
      patch mark_sent_business_invoice_path(business, draft)
      expect(flash[:alert]).to eq("This invoice can't be marked sent while it is sent.")
    end

    it "deletes an invoice without payments, and refuses one with payments" do
      sign_in_as user_with_role("editor", business)
      linked = create(:invoice_payment, invoice: create(:invoice, business: business)).invoice
      delete business_invoice_path(business, linked)
      expect(flash[:alert]).to eq("Unlink its payments before deleting this invoice.")
      expect(Invoice.exists?(linked.id)).to be(true)

      delete business_invoice_path(business, invoice)
      expect(response).to redirect_to(business_invoices_path(business))
      expect(Invoice.exists?(invoice.id)).to be(false)
    end
  end
end
