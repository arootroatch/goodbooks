# Plaid calls this without a session; the signed Plaid-Verification header is the only authentication.
class PlaidWebhooksController < ApplicationController
  include PlaidScoped

  KID_FORMAT = /\A[A-Za-z0-9-]+\z/
  KID_MAX_LENGTH = 64

  allow_unauthenticated_access
  skip_before_action :require_household
  skip_forgery_protection
  rate_limit to: 60, within: 1.minute, with: -> { head :too_many_requests }

  def create
    body = request.raw_post
    verifier.verify!(body: body, token: request.headers["Plaid-Verification"])
    payload = JSON.parse(body)
    handle(payload) if payload.is_a?(Hash)
    head :ok
  rescue PlaidFeed::WebhookVerifier::Invalid => e
    Rails.logger.info("Plaid webhook rejected: #{e.message}")
    head :unauthorized
  rescue JSON::ParserError
    head :bad_request
  end

  private

  def verifier
    PlaidFeed::WebhookVerifier.new(key_fetcher: method(:webhook_key))
  end

  # The kid comes from the unauthenticated request, so it is shape-checked before it reaches Plaid, and a kid
  # Plaid doesn't know is remembered briefly so forged ones can't each cost a call.
  def webhook_key(kid)
    return unless kid.to_s.length <= KID_MAX_LENGTH && kid.to_s.match?(KID_FORMAT)

    missing = "plaid/webhook_key_missing/#{kid}"
    return if Rails.cache.exist?(missing)

    Rails.cache.fetch("plaid/webhook_key/#{kid}", expires_in: 1.hour, skip_nil: true) { PlaidGateway.current.webhook_verification_key(kid) }
  rescue PlaidGateway::TransientError
    raise
  rescue PlaidGateway::Error
    Rails.cache.write(missing, true, expires_in: 5.minutes)
    nil
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
      item.update!(consent_expires_at: parse_time(payload["consent_expiration_time"]) || 7.days.from_now)
    in [ "ITEM", "LOGIN_REPAIRED" ]
      item.update!(status: "ok", last_error: nil, consent_expires_at: nil)
      PlaidSyncJob.perform_later(item)
    else
      nil
    end
  end

  def parse_time(value)
    Time.zone.parse(value) if value.present?
  rescue ArgumentError, TypeError
    nil
  end
end
