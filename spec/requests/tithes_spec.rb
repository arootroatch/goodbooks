require "rails_helper"

RSpec.describe "Tithe" do
  let!(:household) { create(:household) }
  let!(:owner) { create(:user, :household_owner) }
  let!(:book) { PersonalBookProvisioner.call(household) }
  let(:checking) { create(:account, business: book) }
  let(:start_on) { Date.current - 14 }

  def seed_week
    create(:transaction, account: checking, payee: "TRANSFER FROM PAT", amount_cents: 150_000, posted_on: start_on)
    create(:transaction, account: checking, payee: "CHECK 1042 GRACE CHURCH", amount_cents: -10_000, posted_on: start_on + 1,
                         category: book.categories.find_by!(name: "Tithe"))
  end

  it "asks the owner for a start date before showing numbers" do
    sign_in_as owner
    get business_tithe_path(book)
    expect(response.body).to include("Track tithe from")
    expect(response.body).not_to include("Behind")
  end

  it "shows the balance, the weekly rows, and a CSV once a start date is set" do
    seed_week
    book.update!(tithe_start_on: start_on)
    sign_in_as owner
    get business_tithe_path(book)
    expect(response.body).to include("Behind $50.00", "TRANSFER FROM PAT", "CHECK 1042 GRACE CHURCH", "partial")
    get business_tithe_path(book, format: :csv)
    expect(response.media_type).to eq("text/csv")
    expect(response.body.lines.first).to start_with("Week starting,Week ending,Income,Owed")
    get root_path
    expect(response.body).to include("Tithe: Behind $50.00")
  end

  it "saves, rejects, and clears the start date" do
    sign_in_as owner
    patch business_tithe_path(book), params: { business: { tithe_start_on: start_on.iso8601 } }
    expect(response).to redirect_to(business_tithe_path(book))
    expect(book.reload.tithe_start_on).to eq(start_on)

    patch business_tithe_path(book), params: { business: { tithe_start_on: "abc" } }
    expect(flash[:alert]).to eq("Tithe start date is not a valid date.")
    expect(book.reload.tithe_start_on).to eq(start_on)

    patch business_tithe_path(book), params: { business: { tithe_start_on: (Date.current + 1).iso8601 } }
    expect(flash[:alert]).to include("can't be in the future")
    expect(book.reload.tithe_start_on).to eq(start_on)

    patch business_tithe_path(book), params: { business: { tithe_start_on: "" } }
    expect(book.reload.tithe_start_on).to be_nil
  end

  it "lets editors read but not change the start date" do
    spouse = create(:user)
    create(:person, household: household, user: spouse)
    PersonalBookProvisioner.sync(household)
    sign_in_as spouse
    get business_tithe_path(book)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Track tithe from")
    patch business_tithe_path(book), params: { business: { tithe_start_on: start_on.iso8601 } }
    expect(response).to have_http_status(:forbidden)
  end

  it "is not found for non-members and on business books" do
    business = create(:business)
    accountant = user_with_role("viewer", business)
    sign_in_as accountant
    get business_tithe_path(book)
    expect(response).to have_http_status(:not_found)
    get business_tithe_path(book, format: :csv)
    expect(response).to have_http_status(:not_found)
    sign_in_as user_with_role("owner", business)
    get business_tithe_path(business)
    expect(response).to have_http_status(:not_found)
  end
end
