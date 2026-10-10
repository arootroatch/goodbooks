require "rails_helper"

RSpec.describe "docker-compose.yml" do
  let(:app) { YAML.load_file(Rails.root.join("docker-compose.yml")).dig("services", "app") }

  it "reads the master key from the mounted config/master.key, not an env var" do
    expect(app["volumes"]).to include("./config/master.key:/rails/config/master.key:ro")
    expect(app["environment"]).not_to have_key("RAILS_MASTER_KEY")
  end

  it "sets env vars inline instead of interpolating from a .env file" do
    expect(app["environment"]).to have_key("APP_HOST")
    expect(app["environment"].values.join).not_to include("${")
  end
end
