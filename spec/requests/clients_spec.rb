require "rails_helper"

RSpec.describe "Clients" do
  let!(:business) { create(:business) }
  let!(:client) { create(:client, business: business, name: "Acme") }

  it "lists active clients to viewers and hides archived ones until asked" do
    create(:client, business: business, name: "Old Co", archived_at: Time.current)
    sign_in_as user_with_role("viewer", business)
    get business_clients_path(business)
    expect(response.body).to include("Acme")
    expect(response.body).not_to include("Old Co")
    get business_clients_path(business, archived: "1")
    expect(response.body).to include("Old Co")
  end

  it "404s for non-members" do
    sign_in_as create(:user)
    get business_clients_path(business)
    expect(response).to have_http_status(:not_found)
  end

  it "forbids viewers from writing" do
    sign_in_as user_with_role("viewer", business)
    get new_business_client_path(business)
    expect(response).to have_http_status(:forbidden)
    post business_clients_path(business), params: { client: { name: "New" } }
    expect(response).to have_http_status(:forbidden)
    patch business_client_path(business, client), params: { client: { name: "Renamed" } }
    expect(response).to have_http_status(:forbidden)
    expect(client.reload.name).to eq("Acme")
  end

  it "lets editors add, rename, and archive clients" do
    sign_in_as user_with_role("editor", business)
    post business_clients_path(business), params: { client: { name: "Globex", email: "ap@globex.test", notes: "Net 30" } }
    expect(response).to redirect_to(business_clients_path(business))
    expect(business.clients.find_by!(name: "Globex").email).to eq("ap@globex.test")

    patch business_client_path(business, client), params: { client: { name: "Acme Corp", archived: "1" } }
    expect(client.reload.name).to eq("Acme Corp")
    expect(client).to be_archived
    patch business_client_path(business, client), params: { client: { archived: "0" } }
    expect(client.reload).not_to be_archived
  end

  it "re-renders invalid input" do
    sign_in_as user_with_role("editor", business)
    post business_clients_path(business), params: { client: { name: "Acme" } }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "404s for another business's client" do
    other = create(:client)
    sign_in_as user_with_role("owner", business)
    get edit_business_client_path(business, other)
    expect(response).to have_http_status(:not_found)
  end
end
