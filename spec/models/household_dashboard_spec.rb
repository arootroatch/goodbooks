require "rails_helper"

RSpec.describe HouseholdDashboard do
  let(:today) { Date.new(2026, 10, 10) }
  let!(:household) { create(:household) }
  let(:owner) { create(:user, :household_owner) }
  let(:person) { create(:person, household:) }
  let!(:studio) { BusinessProvisioner.call(build(:business, person:, name: "Studio"), owner:) }
  let!(:consulting) { BusinessProvisioner.call(build(:business, person:, name: "Consulting"), owner:) }
  let!(:book) { PersonalBookProvisioner.call(household) }

  def income(business, cents, on: today - 30)
    create(:transaction, account: business.accounts.first, category: business.categories.find_by!(kind: "income"),
                         amount_cents: cents, posted_on: on)
  end

  it "summarizes each business's year to date, open invoices, and inbox" do
    income(studio, 500_000)
    income(studio, 900_000, on: Date.new(2025, 12, 31))
    create(:transaction, account: consulting.accounts.first, amount_cents: -2_000, posted_on: today)
    create(:invoice, business: studio, amount_cents: 120_000, due_date: today - 5)
    create(:invoice, business: consulting, amount_cents: 80_000, due_date: today + 5)

    dashboard = described_class.new(user: owner, today:)
    expect(dashboard.businesses.map { _1.business.name }).to eq(%w[Consulting Studio])
    row = dashboard.businesses.find { _1.business == studio }
    expect(row.report.total_income_cents).to eq(500_000)
    expect(row.overdue_cents).to eq(120_000)
    expect(row.outstanding_cents).to eq(120_000)
    expect(dashboard.businesses.find { _1.business == consulting }.inbox_count).to eq(1)
    expect(dashboard.business_net_cents).to eq(500_000)
    expect(dashboard.open_invoices.overdue.total_cents).to eq(120_000)
    expect(dashboard.open_invoices.outstanding_cents).to eq(200_000)
    expect(dashboard.inbox_count).to eq(1)
  end

  it "includes the personal book's year and tithe for household members" do
    checking = create(:account, business: book)
    create(:transaction, account: checking, category: book.categories.find_by!(name: "Groceries"), amount_cents: -4_200, posted_on: today)
    create(:transaction, account: checking, amount_cents: -100, posted_on: today)
    book.update!(tithe_start_on: today - 14)

    dashboard = described_class.new(user: owner, today:)
    expect(dashboard.book).to eq(book)
    expect(dashboard.personal.total_expense_cents).to eq(4_200)
    expect(dashboard.tithe).to be_a(Tithe::Ledger)
    expect(dashboard.inbox_count).to eq(1)
  end

  it "only covers businesses the user can access, and no personal book for the accountant" do
    accountant = create(:user)
    create(:membership, user: accountant, business: studio, role: "viewer")
    create(:invoice, business: consulting, amount_cents: 80_000, due_date: today - 5)

    dashboard = described_class.new(user: accountant, today:)
    expect(dashboard.businesses.map(&:business)).to eq([ studio ])
    expect(dashboard.open_invoices.outstanding_cents).to eq(0)
    expect(dashboard.book).to be_nil
    expect(dashboard.personal).to be_nil
    expect(dashboard.tithe).to be_nil
  end
end
