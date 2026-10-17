require "rails_helper"

RSpec.describe "docker-compose.yml" do
  let(:app) { YAML.load_file(Rails.root.join("docker-compose.yml")).dig("services", "app") }

  it "runs the published image rather than building from source" do
    expect(app["image"]).to start_with("ghcr.io/arootroatch/goodbooks:")
    expect(app).not_to have_key("build")
  end

  it "sets env vars inline instead of interpolating from a .env file" do
    expect(app).not_to have_key("env_file")
    expect(app["environment"]).to include("APP_HOST", "SECRET_KEY_BASE", *Secrets::ENCRYPTION_KEYS.map { Secrets.variable(_1) })
    expect(app["environment"].values.join).not_to include("${")
  end

  it "ships every secret blank so the template never carries real ones" do
    secrets = %w[SECRET_KEY_BASE PLAID_SECRET] + Secrets::ENCRYPTION_KEYS.map { Secrets.variable(_1) }
    expect(app["environment"].slice(*secrets).values).to all(eq(""))
  end

  it "rotates the app's logs" do
    expect(app["logging"]).to eq("driver" => "json-file", "options" => { "max-size" => "10m", "max-file" => "5" })
  end
end
