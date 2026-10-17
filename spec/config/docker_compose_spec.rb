require "rails_helper"

RSpec.describe "docker-compose.yml" do
  let(:app) { YAML.load_file(Rails.root.join("docker-compose.yml")).dig("services", "app") }
  let(:settings) { %w[APP_HOST TIME_ZONE SECRET_KEY_BASE PLAID_CLIENT_ID PLAID_SECRET PLAID_ENV] + Secrets::ENCRYPTION_KEYS.map { Secrets.variable(_1) } }

  it "runs the published image rather than building from source" do
    expect(app["image"]).to eq("ghcr.io/arootroatch/goodbooks:${GOODBOOKS_VERSION:-latest}")
    expect(app).not_to have_key("build")
  end

  it "reads every setting from .env, so the file itself never needs editing" do
    expect(Array(app["env_file"])).to eq([ ".env" ])
    expect(app.fetch("environment", {}).keys & settings).to be_empty
    expect(YAML.dump(app.except("image"))).not_to include("${")
  end

  it "rotates the app's logs" do
    expect(app["logging"]).to eq("driver" => "json-file", "options" => { "max-size" => "10m", "max-file" => "5" })
  end
end

RSpec.describe ".env.example" do
  let(:example) do
    Rails.root.join(".env.example").read.lines.filter_map { _1.strip.match(/\A([A-Z_]+)=(.*)\z/)&.captures }.to_h
  end

  it "lists every setting the app reads" do
    expect(example.keys).to include("GOODBOOKS_VERSION", "APP_HOST", "TIME_ZONE", "SECRET_KEY_BASE", "PLAID_CLIENT_ID", "PLAID_SECRET", "PLAID_ENV",
                                    *Secrets::ENCRYPTION_KEYS.map { Secrets.variable(_1) })
  end

  it "ships every secret blank so the template never carries real ones" do
    secrets = %w[SECRET_KEY_BASE PLAID_SECRET] + Secrets::ENCRYPTION_KEYS.map { Secrets.variable(_1) }
    expect(example.slice(*secrets).values).to all(eq(""))
  end
end
