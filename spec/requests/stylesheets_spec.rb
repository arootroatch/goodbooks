require "rails_helper"

RSpec.describe "Stylesheets" do
  before { create(:household) }

  it "links the design system stylesheets and serves the fonts they reference" do
    get new_session_path
    hrefs = Nokogiri::HTML(response.body).css("link[rel=stylesheet]").map { _1[:href] }
    expect(hrefs).to include(a_string_matching(%r{/assets/tokens-}), a_string_matching(%r{/assets/fonts-}), a_string_matching(%r{/assets/base-}))

    get hrefs.find { _1.include?("/assets/fonts-") }
    font_urls = response.body.scan(/url\("([^"]+\.woff2)"\)/).flatten
    expect(font_urls.size).to eq(5)
    font_urls.each do |url|
      get url
      expect(response).to have_http_status(:ok)
    end
  end
end
