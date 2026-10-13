require "rails_helper"

RSpec.describe "Estimated payments" do
  let!(:household) { create(:household) }
  let!(:business) { create(:business, household:) }
  let!(:personal) { create(:business, :personal, household:) }
  let!(:owner) do
    create(:user, :household_owner).tap do |user|
      create(:membership, user:, business:, role: "owner")
      create(:membership, user:, business: personal, role: "owner")
    end
  end
  let(:joint) { create(:account, business: personal, name: "Joint Checking") }
  let!(:irs) { create(:transaction, account: joint, payee: "IRS USATAXPYMT", posted_on: Date.new(2026, 6, 12), amount_cents: -450_000) }

  it "lists candidates and records a payment from the picked debit" do
    sign_in_as owner
    get new_tax_year_estimated_payment_path(2026, q: "IRS")
    expect(response.body).to include("IRS USATAXPYMT")
    post tax_year_estimated_payments_path(2026), params: { estimated_payment: { debit_id: irs.id } }
    expect(response).to redirect_to(tax_year_path(2026))
    expect(EstimatedPayment.last).to have_attributes(debit: irs, amount_cents: 450_000, paid_on: Date.new(2026, 6, 12), quarter: 2)
  end

  it "records a payment by hand with the quarter from its date" do
    sign_in_as owner
    post tax_year_estimated_payments_path(2026), params: { estimated_payment: { paid_on: "2026-04-15", amount: "1,200", quarter: "" } }
    expect(EstimatedPayment.last).to have_attributes(debit: nil, amount_cents: 120_000, quarter: 1)
  end

  it "refuses money in" do
    deposit = create(:transaction, account: joint, amount_cents: 5_000, posted_on: Date.new(2026, 6, 1))
    sign_in_as owner
    post tax_year_estimated_payments_path(2026), params: { estimated_payment: { debit_id: deposit.id } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("must be money paid out")
    expect(EstimatedPayment.count).to eq(0)
    expect(TaxYear.count).to eq(0)
    expect(Nokogiri::HTML(response.body).at_css("input[name='estimated_payment[amount]']")["value"]).to be_blank
  end

  it "refuses a debit already recorded" do
    sign_in_as owner
    2.times { post tax_year_estimated_payments_path(2026), params: { estimated_payment: { debit_id: irs.id } } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("is already recorded as a payment")
    expect(EstimatedPayment.count).to eq(1)
  end

  it "404s a debit in a book the user can't see" do
    hidden = create(:transaction, account: create(:account, business: create(:business, household:)), amount_cents: -100)
    sign_in_as owner
    post tax_year_estimated_payments_path(2026), params: { estimated_payment: { debit_id: hidden.id } }
    expect(response).to have_http_status(:not_found)
    expect(TaxYear.count).to eq(0)
  end

  it "leaves no tax year behind when a hand entry is invalid" do
    sign_in_as owner
    post tax_year_estimated_payments_path(2026), params: { estimated_payment: { paid_on: "2026-04-15", amount: "0" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(TaxYear.count).to eq(0)
  end

  it "doesn't prefill the hand-entry form with a refused debit" do
    sign_in_as owner
    2.times { post tax_year_estimated_payments_path(2026), params: { estimated_payment: { debit_id: irs.id } } }
    form = Nokogiri::HTML(response.body).at_css("form[action='#{tax_year_estimated_payments_path(2026)}'] input[name='estimated_payment[paid_on]']")
    expect(form["value"]).to be_blank
    expect(response.body).not_to include("4,500.00\"")
  end

  it "says a payment linked to a hidden book is linked to a bank transaction, once" do
    hidden = create(:transaction, account: create(:account, business: create(:business, household:)), amount_cents: -100, posted_on: Date.new(2026, 4, 1))
    payment = create(:estimated_payment, tax_year: create(:tax_year, household:), debit: hidden, paid_on: hidden.posted_on, amount_cents: 100)
    sign_in_as owner
    get edit_tax_year_estimated_payment_path(2026, payment)
    expect(response.body).to include("Linked to a bank transaction.")
    expect(response.body).not_to include("Linked to Linked")
  end

  it "edits and deletes a payment" do
    payment = create(:estimated_payment, tax_year: create(:tax_year, household:), amount_cents: 100_000)
    sign_in_as owner
    patch tax_year_estimated_payment_path(2026, payment), params: { estimated_payment: { amount: "1,500", quarter: "3" } }
    expect(payment.reload).to have_attributes(amount_cents: 150_000, quarter: 3)
    delete tax_year_estimated_payment_path(2026, payment)
    expect(EstimatedPayment.count).to eq(0)
  end

  it "404s a payment from another year's URL" do
    payment = create(:estimated_payment, tax_year: create(:tax_year, household:, year: 2025))
    sign_in_as owner
    get edit_tax_year_estimated_payment_path(2026, payment)
    expect(response).to have_http_status(:not_found)
  end

  it "forbids a viewer of every business" do
    sign_in_as user_with_role("viewer", business)
    get new_tax_year_estimated_payment_path(2026)
    expect(response).to have_http_status(:forbidden)
    post tax_year_estimated_payments_path(2026), params: { estimated_payment: { paid_on: "2026-04-15", amount: "1" } }
    expect(response).to have_http_status(:forbidden)
  end
end
