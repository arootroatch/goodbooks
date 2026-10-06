# Controllers capture ActionController::Base.cache_store when they declare rate_limit, and the test
# env uses a null store. This context routes that store's counters through a real memory store.
RSpec.shared_context "with rate limiting" do
  before do
    memory = ActiveSupport::Cache::MemoryStore.new
    allow(ActionController::Base.cache_store).to receive(:increment) { |*args, **opts| memory.increment(*args, **opts) }
  end
end
