require "rails_helper"

RSpec.describe "Installable app" do
  before { create(:household) }

  def head = Nokogiri::HTML(response.body).at("head")

  def theme_colors = head.css("meta[name=theme-color]").to_h { [ _1[:media], _1[:content] ] }

  it "links a manifest and theme colors for both color schemes" do
    get new_session_path
    expect(head.at("link[rel=manifest]")[:href]).to eq("/manifest.json")
    expect(theme_colors).to eq("(prefers-color-scheme: light)" => "#ffffff", "(prefers-color-scheme: dark)" => "#0e1020")
    expect(head.at("meta[name=viewport]")[:content]).to include("viewport-fit=cover")
    expect(head.at("meta[name=apple-mobile-web-app-title]")[:content]).to eq("Goodbooks")
  end

  it "pins the theme color to the theme chosen in the toggle" do
    cookies[:theme] = "dark"
    get new_session_path
    expect(theme_colors).to eq("not all" => "#ffffff", "all" => "#0e1020")
  end

  it "serves a standalone manifest with the 512px icon, without signing in" do
    get "/manifest.json"
    expect(response).to have_http_status(:ok)
    manifest = response.parsed_body
    expect(manifest).to include("name" => "Goodbooks", "short_name" => "Goodbooks", "display" => "standalone", "start_url" => "/")
    expect(manifest["icons"]).to contain_exactly(
      a_hash_including("src" => %r{\A/assets/icon-\h+\.png\z}, "sizes" => "512x512"),
      a_hash_including("src" => %r{\A/assets/icon-maskable-\h+\.png\z}, "sizes" => "512x512", "purpose" => "maskable")
    )
  end

  it "does not serve a service worker" do
    get "/service-worker.js"
    expect(response).to have_http_status(:not_found)
  end
end
