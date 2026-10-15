require "rails_helper"

RSpec.describe Account, "balances" do
  let(:account) { create(:account, opening_balance: "1,000.00", opening_balance_on: Date.new(2026, 1, 31)) }

  it "is unknown without an opening balance" do
    expect(create(:account).balance_cents).to be_nil
    expect(create(:account)).not_to be_balance_known
  end

  it "adds non-excluded transactions posted after the opening date" do
    create(:transaction, account: account, posted_on: Date.new(2026, 1, 31), amount_cents: -999_99)
    create(:transaction, account: account, posted_on: Date.new(2026, 2, 1), amount_cents: -250_00)
    create(:transaction, account: account, posted_on: Date.new(2026, 2, 2), amount_cents: 50_00)
    create(:transaction, account: account, posted_on: Date.new(2026, 2, 3), amount_cents: -10_00, excluded: true)
    create(:transaction, account: account, posted_on: Date.new(2026, 2, 4), amount_cents: -100_00, transfer: true)
    expect(account.balance_cents).to eq(1_000_00 - 250_00 + 50_00 - 100_00)
    expect(account).to be_balance_known
  end

  it "uses the reported balance for Plaid accounts and ignores transactions" do
    plaid = create(:account, :plaid)
    expect(plaid.balance_cents).to be_nil
    plaid.update!(reported_balance_cents: 4_321_00, balance_reported_at: Time.current)
    create(:transaction, account: plaid, amount_cents: -5_00)
    expect(plaid.balance_cents).to eq(4_321_00)
  end

  it "requires the opening amount and date together" do
    expect(build(:account, opening_balance: "10", opening_balance_on: nil)).to have_error_on(:opening_balance_on)
    expect(build(:account, opening_balance: "", opening_balance_on: Date.current)).to have_error_on(:opening_balance)
    expect(build(:account, opening_balance: "abc", opening_balance_on: Date.current)).not_to be_valid
    expect(build(:account, opening_balance: "-25.00", opening_balance_on: Date.current)).to be_valid
  end

  def have_error_on(attr) = satisfy { |record| !record.valid? && record.errors[attr].any? }
end
