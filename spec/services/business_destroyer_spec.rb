require "rails_helper"

RSpec.describe BusinessDestroyer do
  let(:owner) { create(:user, :household_owner) }
  let(:business) { BusinessProvisioner.call(build(:business, name: "Personal"), owner: owner) }

  def populate(book)
    account = book.accounts.first
    category = book.categories.first
    rule = create(:rule, business: book, category: category)
    goal = create(:goal, business: book)
    create(:transaction, account: account, category: category, rule: rule, goal: goal)
    create(:mileage_entry, business: book)
    create(:home_office, business: book)
    create(:sales_tax_filing, business: create(:sales_tax_profile, business: book).business)
  end

  it "deletes the business and everything in it" do
    populate(business)
    other = BusinessProvisioner.call(build(:business, name: "Keep Co"), owner: owner)
    populate(other)

    result = BusinessDestroyer.call(business)

    expect(result).to be_ok
    expect(Business.exists?(business.id)).to be(false)
    [ Account, Category, Rule, Goal, MileageEntry, HomeOffice, SalesTaxProfile, SalesTaxFiling, Membership ].each do |model|
      expect(model.where(business_id: business.id)).to be_empty, model.name
      expect(model.where(business_id: other.id)).to exist, model.name
    end
    expect(Transaction.for_businesses(other.id)).to exist
    expect(Transaction.count).to eq(1)
  end

  it "unlinks an estimated payment that pointed at one of its transactions" do
    debit = create(:transaction, account: business.accounts.first)
    payment = create(:estimated_payment, debit: debit)
    expect(BusinessDestroyer.call(business)).to be_ok
    expect(payment.reload.debit_id).to be_nil
  end

  it "drops its invite grants and any pending invite left with no grants" do
    other = BusinessProvisioner.call(build(:business, name: "Keep Co"), owner: owner)
    only_this = create(:invite, business: business)
    both = create(:invite, business: business)
    both.grants.create!(business: other, role: "viewer")

    expect(BusinessDestroyer.call(business)).to be_ok
    expect(Invite.exists?(only_this.id)).to be(false)
    expect(both.reload.grants.map(&:business)).to eq([ other ])
  end

  it "writes one audit summary" do
    business
    Audit.as(owner) { BusinessDestroyer.call(business) }
    expect(AuditEvent.pluck(:action, :summary, :business_id)).to eq([ [ "summary", "Deleted book Personal", business.id ] ])
  end

  describe "refusing" do
    it "refuses the personal book" do
      book = PersonalBookProvisioner.call(Household.first || create(:household))
      result = BusinessDestroyer.call(book)
      expect(result.errors).to eq([ "The personal book can't be deleted." ])
      expect(Business.exists?(book.id)).to be(true)
    end

    it "refuses a business with invoices or clients" do
      create(:client, business: business)
      result = BusinessDestroyer.call(business)
      expect(result.errors).to eq([ "Delete this business's invoices and clients first." ])
      expect(Business.exists?(business.id)).to be(true)
    end

    it "refuses a business with an account still fed by Plaid, archived ones included" do
      create(:account, :plaid, business: business, archived_at: Time.current)
      result = BusinessDestroyer.call(business)
      expect(result.errors).to eq([ "Unlink this business's bank accounts from Plaid first." ])
      expect(Business.exists?(business.id)).to be(true)
    end
  end
end
