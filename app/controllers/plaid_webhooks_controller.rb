# Plaid calls this without a session; the signed Plaid-Verification header is the only authentication.
class PlaidWebhooksController < ApplicationController
  include PlaidScoped

  allow_unauthenticated_access
  skip_before_action :require_household
  skip_forgery_protection
  rate_limit to: 60, within: 1.minute, with: -> { head :too_many_requests }

  def create
    body = request.raw_post
    verifier.verify!(body: body, token: request.headers["Plaid-Verification"])
    handle(JSON.parse(body))
    head :ok
  rescue PlaidFeed::WebhookVerifier::Invalid => e
    Rails.logger.info("Plaid webhook rejected: #{e.message}")
    head :unauthorized
  rescue JSON::ParserError
    head :bad_request
  end

  private

  def verifier
    PlaidFeed::WebhookVerifier.new(key_fetcher: lambda { |kid|
      Rails.cache.fetch("plaid/webhook_key/#{kid}", expires_in: 24.hours) { PlaidGateway.current.webhook_verification_key(kid) }
    })
  end

  def handle(payload)
    item = PlaidItem.find_by(item_id: payload["item_id"].to_s)
    return unless item

    case [ payload["webhook_type"], payload["webhook_code"] ]
    in [ "TRANSACTIONS", "SYNC_UPDATES_AVAILABLE" ]
      PlaidSyncJob.perform_later(item)
    in [ "ITEM", "ERROR" ] if payload.dig("error", "error_code") == "ITEM_LOGIN_REQUIRED"
      item.update!(status: "login_required", last_error: "ITEM_LOGIN_REQUIRED: #{payload.dig("error", "error_message")}")
    in [ "ITEM", "PENDING_EXPIRATION" | "PENDING_DISCONNECT" ]
      item.update!(status: "login_required")
    in [ "ITEM", "LOGIN_REPAIRED" ]
      item.update!(status: "ok", last_error: nil)
      PlaidSyncJob.perform_later(item)
    else
      nil
    end
  end
end
