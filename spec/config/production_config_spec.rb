require "rails_helper"

RSpec.describe "Production host configuration" do
  it "allows APP_HOST and keeps /up reachable for health checks" do
    config = File.read(Rails.root.join("config/environments/production.rb"))
    expect(config).to include('config.hosts = [ENV.fetch("APP_HOST", "localhost")]')
    expect(config).to include("config.host_authorization = { exclude: ->(request) { request.path == \"/up\" } }")
    expect(config).to include("config.assume_ssl = true")
    expect(config).to include("config.force_ssl = true")
  end
end
