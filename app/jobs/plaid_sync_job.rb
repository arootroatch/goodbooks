class PlaidSyncJob < ApplicationJob
  limits_concurrency to: 1, key: ->(item) { item }

  retry_on PlaidGateway::TransientError, wait: :polynomially_longer, attempts: 5 do |job, error|
    job.arguments.first.update!(status: "error", last_error: error.message)
  end

  def perform(item)
    return if item.login_required? || !PlaidGateway.enabled?

    PlaidFeed::Sync.call(item)
  rescue PlaidGateway::LoginRequired => e
    item.update!(status: "login_required", last_error: e.message)
  rescue PlaidGateway::TransientError => e
    item.update!(last_error: e.message)
    raise
  rescue PlaidGateway::Error, PlaidFeed::TransactionMapper::InvalidAmount => e
    item.update!(status: "error", last_error: e.message)
  end
end
