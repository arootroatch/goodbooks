require "rails_helper"

RSpec.describe "Theme" do
  before { create(:household) }

  def html_theme = Nokogiri::HTML(response.body).at("html")["data-theme"]

  it "renders the cookie's theme on <html>" do
    cookies[:theme] = "dark"
    get new_session_path
    expect(html_theme).to eq("dark")
  end

  it "renders light" do
    cookies[:theme] = "light"
    get new_session_path
    expect(html_theme).to eq("light")
  end

  it "omits the attribute for system, missing, or tampered values" do
    [ "system", "blue", "\"><script>alert(1)</script>" ].each do |value|
      cookies[:theme] = value
      get new_session_path
      expect(html_theme).to be_nil
      expect(response.body).not_to include("<script>alert(1)")
    end
  end

  it "renders the toggle with the current choice pressed" do
    cookies[:theme] = "dark"
    get new_session_path
    toggle = Capybara.string(response.body).find(".theme-toggle")
    expect(toggle).to have_css('button[aria-pressed="true"]', text: "Dark")
    expect(toggle).to have_css('button[aria-pressed="false"]', text: "System")
    expect(toggle).to have_css('button[aria-pressed="false"]', text: "Light")
  end

  it "shows the toggle to signed-in users" do
    business = create(:business)
    sign_in_as user_with_role("viewer", business)
    get root_path
    expect(Capybara.string(response.body).find("nav.sidebar")).to have_css(".theme-toggle")
  end

  describe "PATCH /theme" do
    it "stores a valid choice and redirects back" do
      patch theme_path, params: { theme: "dark" }, headers: { "HTTP_REFERER" => "http://www.example.com/session/new" }
      expect(response).to redirect_to("http://www.example.com/session/new")
      expect(cookies[:theme]).to eq("dark")
    end

    it "ignores unknown values" do
      patch theme_path, params: { theme: "neon" }
      expect(response).to redirect_to(root_path)
      expect(cookies[:theme]).to be_blank
    end

    it "works for signed-in users" do
      business = create(:business)
      sign_in_as user_with_role("viewer", business)
      patch theme_path, params: { theme: "light" }
      expect(cookies[:theme]).to eq("light")
    end
  end
end
