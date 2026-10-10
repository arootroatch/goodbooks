require "rails_helper"

RSpec.describe "Invoice PDFs" do
  let!(:business) { create(:business) }
  let!(:invoice) { create(:invoice, business: business) }
  let(:pdf) { fixture_file_upload("invoice.pdf", "application/pdf") }

  it "lets editors upload a PDF and members view it inline" do
    sign_in_as user_with_role("editor", business)
    patch business_invoice_path(business, invoice), params: { invoice: { pdf: pdf } }
    expect(invoice.reload.pdf).to be_attached

    sign_in_as user_with_role("viewer", business)
    get business_invoice_pdf_path(business, invoice)
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/pdf")
    expect(response.headers["Content-Disposition"]).to start_with("inline")
    expect(response.body).to start_with("%PDF")
  end

  it "404s when there is no PDF, for non-members, and across businesses" do
    sign_in_as user_with_role("viewer", business)
    get business_invoice_pdf_path(business, invoice)
    expect(response).to have_http_status(:not_found)

    other = create(:invoice)
    other.pdf.attach(io: file_fixture("invoice.pdf").open, filename: "invoice.pdf")
    other.save!
    get business_invoice_pdf_path(business, other)
    expect(response).to have_http_status(:not_found)

    sign_in_as create(:user)
    get business_invoice_pdf_path(other.business, other)
    expect(response).to have_http_status(:not_found)
  end

  it "re-renders a non-PDF upload" do
    sign_in_as user_with_role("editor", business)
    patch business_invoice_path(business, invoice), params: { invoice: { pdf: fixture_file_upload("checking.csv", "text/csv") } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(invoice.reload.pdf).not_to be_attached
  end
end
