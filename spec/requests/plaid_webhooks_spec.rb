require "rails_helper"

RSpec.describe "Plaid webhooks" do
  let!(:item) { create(:plaid_item, item_id: "item-1") }

  def deliver(payload, token: :sign, raw: nil)
    body = raw || payload.to_json
    token = plaid_gateway.sign_webhook(body) if token == :sign
    headers = { "CONTENT_TYPE" => "application/json" }
    headers["Plaid-Verification"] = token if token
    post plaid_webhooks_path, params: body, headers: headers
  end

  def sync_available(item_id = "item-1") = { webhook_type: "TRANSACTIONS", webhook_code: "SYNC_UPDATES_AVAILABLE", item_id: item_id }

  it "starts a sync when Plaid says updates are available, without a login" do
    expect { deliver(sync_available) }.to have_enqueued_job(PlaidSyncJob).with(item)
    expect(response).to have_http_status(:ok)
  end

  it "marks the item login_required on a login error or a pending expiration" do
    deliver({ webhook_type: "ITEM", webhook_code: "ERROR", item_id: "item-1",
              error: { error_code: "ITEM_LOGIN_REQUIRED", error_message: "the login details have changed" } })
    expect(item.reload).to have_attributes(status: "login_required", last_error: "ITEM_LOGIN_REQUIRED: the login details have changed")
    item.update!(status: "ok")
    deliver({ webhook_type: "ITEM", webhook_code: "PENDING_EXPIRATION", item_id: "item-1" })
    expect(item.reload).to be_login_required
  end

  it "marks the item ok and syncs when the login is repaired" do
    item.update!(status: "login_required", last_error: "x")
    expect { deliver({ webhook_type: "ITEM", webhook_code: "LOGIN_REPAIRED", item_id: "item-1" }) }.to have_enqueued_job(PlaidSyncJob)
    expect(item.reload).to have_attributes(status: "ok", last_error: nil)
  end

  it "acknowledges unknown items and webhook types without doing anything" do
    expect { deliver(sync_available("item-unknown")) }.not_to have_enqueued_job
    expect(response).to have_http_status(:ok)
    expect { deliver({ webhook_type: "TRANSACTIONS", webhook_code: "RECURRING_TRANSACTIONS_UPDATE", item_id: "item-1" }) }.not_to have_enqueued_job
    expect(response).to have_http_status(:ok)
  end

  it "rejects unverified requests with 401" do
    other_key = OpenSSL::PKey::EC.generate("prime256v1")
    body = sync_available.to_json
    [
      nil,
      "garbage",
      plaid_gateway.sign_webhook(body, key: other_key),
      plaid_gateway.sign_webhook(body, iat: 6.minutes.ago.to_i),
      plaid_gateway.sign_webhook(sync_available("item-2").to_json)
    ].each do |token|
      expect { deliver(nil, token: token, raw: body) }.not_to have_enqueued_job
      expect(response).to have_http_status(:unauthorized)
    end
    plaid_gateway.expire_key!
    deliver(sync_available)
    expect(response).to have_http_status(:unauthorized)
  end

  it "returns 400 for a verified body that isn't JSON" do
    deliver(nil, raw: "not json")
    expect(response).to have_http_status(:bad_request)
  end

  it "404s when Plaid is disabled" do
    PlaidGateway.current = nil
    post plaid_webhooks_path, params: "{}", headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:not_found)
  end

  context "with rate limiting" do
    include_context "with rate limiting"

    it "allows 60 requests a minute" do
      60.times { deliver(nil, token: "garbage", raw: "{}") }
      expect(response).to have_http_status(:unauthorized)
      deliver(nil, token: "garbage", raw: "{}")
      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
