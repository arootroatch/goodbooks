require "rails_helper"

RSpec.describe Transaction, "goal links" do
  let(:book) { create(:business) }
  let(:txn) { create(:transaction, account: create(:account, business: book)) }

  it "links to a payment goal in its book" do
    goal = create(:goal, business: book)
    expect(txn.update(goal: goal, goal_linked_by: "user")).to be(true)
  end

  it "rejects another book's goal, a savings goal, and unknown link sources" do
    expect(txn.update(goal: create(:goal))).to be(false)
    expect(txn.errors[:goal]).to be_present
    expect(txn.update(goal: create(:goal, :savings, business: book))).to be(false)
    expect(txn.reload.update(goal_linked_by: "robot")).to be(false)
  end
end
