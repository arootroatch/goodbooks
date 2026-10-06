require "rails_helper"

RSpec.describe "Health check" do
  it "responds OK at /up" do
    get "/up"
    expect(response).to have_http_status(:ok)
  end
end
