require "rails_helper"

RSpec.describe Transaction do
  let(:account) { create(:account, :plaid) }

  it "is imported when it has a CSV hash or a Plaid id" do
    expect(build(:transaction, account: account)).not_to be_imported
    expect(build(:transaction, account: account, external_id: "abc")).to be_imported
    expect(build(:transaction, account: account, plaid_transaction_id: "p-1")).to be_imported
  end

  it "keeps Plaid ids unique per account" do
    create(:transaction, account: account, plaid_transaction_id: "p-1")
    expect { create(:transaction, account: account, plaid_transaction_id: "p-1") }.to raise_error(ActiveRecord::RecordNotUnique)
    expect(create(:transaction, account: create(:account, :plaid), plaid_transaction_id: "p-1")).to be_persisted
  end

  it "flags rows for review with a known reason" do
    flagged = create(:transaction, account: account, review_reason: "removed_by_bank")
    create(:transaction, account: account)
    expect(Transaction.needs_review).to eq([ flagged ])
    expect(flagged.review_message).to eq("Removed by the bank")
    expect(build(:transaction, account: account, review_reason: "bogus")).not_to be_valid
  end
end
