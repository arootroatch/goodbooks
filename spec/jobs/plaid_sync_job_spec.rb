require "rails_helper"

RSpec.describe PlaidSyncJob do
  let!(:item) { create(:plaid_item, access_token: "access-1") }
  let!(:account) { create(:account, :plaid, plaid_item: item, plaid_account_id: "acc-1") }

  def plaid(id, amount:)
    FakePlaidGateway.plaid_txn(id, account_id: "acc-1", amount: amount, date: Date.new(2026, 10, 1), name: "X")
  end

  it "syncs the item" do
    plaid_gateway.add_page("access-1", added: [ plaid("t1", amount: 1.0) ])
    described_class.perform_now(item)
    expect(account.transactions.count).to eq(1)
  end

  it "marks the item login_required and does not retry" do
    plaid_gateway.fail_next(:transactions_sync, PlaidGateway::LoginRequired.new("ITEM_LOGIN_REQUIRED: log in again"))
    expect { described_class.perform_now(item) }.not_to have_enqueued_job(described_class)
    expect(item.reload).to have_attributes(status: "login_required", last_error: "ITEM_LOGIN_REQUIRED: log in again")
  end

  it "skips an item that needs reconnecting" do
    item.update!(status: "login_required")
    described_class.perform_now(item)
    expect(plaid_gateway.calls).to be_empty
  end

  it "retries transient errors, recording the last error, and marks the item errored when retries run out" do
    plaid_gateway.fail_next(:transactions_sync, PlaidGateway::TransientError.new("HTTP 500: down"))
    expect { described_class.perform_now(item) }.to have_enqueued_job(described_class).with(item)
    expect(item.reload).to have_attributes(status: "ok", last_error: "HTTP 500: down")

    plaid_gateway.fail_next(:transactions_sync, PlaidGateway::TransientError.new("HTTP 500: still down"))
    job = described_class.new(item)
    job.exception_executions = { [ PlaidGateway::TransientError ].to_s => 4 }
    job.perform_now
    expect(item.reload).to have_attributes(status: "error", last_error: "HTTP 500: still down")
  end

  it "marks the item errored on a permanent Plaid error or an unusable amount" do
    plaid_gateway.fail_next(:transactions_sync, PlaidGateway::Error.new("INVALID_ACCESS_TOKEN: bad"))
    described_class.perform_now(item)
    expect(item.reload).to have_attributes(status: "error", last_error: "INVALID_ACCESS_TOKEN: bad")

    item.update!(status: "ok")
    plaid_gateway.add_page("access-1", added: [ plaid("t1", amount: 1.005) ])
    described_class.perform_now(item)
    expect(item.reload.status).to eq("error")
    expect(item.last_error).to include("not a whole number of cents")
  end

  it "records only the class of an unexpected error, marks the item errored, and re-raises without retrying" do
    plaid_gateway.add_page("access-1", added: [ plaid("t1", amount: nil) ])
    expect {
      expect { described_class.perform_now(item) }.to raise_error(ArgumentError)
    }.not_to have_enqueued_job(described_class)
    expect(item.reload).to have_attributes(status: "error", last_error: "Unexpected error (ArgumentError)", cursor: nil)
  end

  it "does nothing when Plaid is disabled" do
    fake = plaid_gateway
    PlaidGateway.current = nil
    described_class.perform_now(item)
    expect(fake.calls).to be_empty
    expect(item.reload.status).to eq("ok")
  end

  it "never runs two syncs of the same item at once" do
    expect(described_class.new(item).concurrency_key).to eq("PlaidSyncJob/PlaidItem/#{item.id}")
    expect(described_class.concurrency_limit).to eq(1)
  end
end
