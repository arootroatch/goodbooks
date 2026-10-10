require "rails_helper"

RSpec.describe "App icon" do
  let(:rails_default_png_sha256) { "2e29c62b03e514c5a15f289f8fdc0abca6e22d0e91970503c9e2b7e0552c911c" }

  let(:svg) { Rails.public_path.join("icon.svg").read }
  let(:png) { Rails.public_path.join("icon.png").binread }

  it "draws the svg in the brand indigo" do
    expect(svg).to include("#4f46e5")
    expect(svg).not_to include('fill="red"')
  end

  it "ships a 512px png that replaces the Rails placeholder" do
    expect(png[16, 8].unpack("NN")).to eq([ 512, 512 ])
    expect(Digest::SHA256.hexdigest(png)).not_to eq(rails_default_png_sha256)
  end
end
