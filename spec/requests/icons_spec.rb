require "rails_helper"

RSpec.describe "App icons" do
  let(:rails_default_png_sha256) { "2e29c62b03e514c5a15f289f8fdc0abca6e22d0e91970503c9e2b7e0552c911c" }

  before { create(:household) }

  def icon_links
    get new_session_path
    Nokogiri::HTML(response.body).css("link[rel=icon], link[rel=apple-touch-icon]").to_h { [ "#{_1[:rel]} #{_1[:type]}", _1[:href] ] }
  end

  it "links fingerprinted icons so browsers refetch them when they change" do
    expect(icon_links).to match(
      "icon image/svg+xml" => %r{\A/assets/icon-\h+\.svg\z},
      "icon image/png" => %r{\A/assets/icon-\h+\.png\z},
      "apple-touch-icon image/png" => %r{\A/assets/icon-\h+\.png\z}
    )
  end

  it "serves the indigo svg" do
    get icon_links.fetch("icon image/svg+xml")
    expect(response.body).to include("#4f46e5")
    expect(response.body).not_to include('fill="red"')
  end

  it "serves a 512px png that replaces the Rails placeholder" do
    get icon_links.fetch("icon image/png")
    png = response.body.b
    expect(png[16, 8].unpack("NN")).to eq([ 512, 512 ])
    expect(Digest::SHA256.hexdigest(png)).not_to eq(rails_default_png_sha256)
  end
end
