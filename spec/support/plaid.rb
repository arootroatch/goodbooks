module PlaidHelpers
  def plaid_gateway = PlaidGateway.current
end

RSpec.configure do |config|
  config.include PlaidHelpers
  config.before { PlaidGateway.current = FakePlaidGateway.new }
  config.after { PlaidGateway.reset! }
end
