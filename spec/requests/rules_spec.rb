require "rails_helper"

RSpec.describe "Rules" do
  let!(:business) { create(:business) }
  let!(:category) { create(:category, business: business, name: "Software") }

  it "lets editors create a rule" do
    sign_in_as user_with_role("editor", business)
    post business_rules_path(business), params: { rule: {
      field: "payee", operator: "contains", value: "adobe", outcome: "categorize", category_id: category.id, amount_min: "", amount_max: ""
    } }
    expect(response).to redirect_to(business_rules_path(business))
    expect(business.rules.sole.value).to eq("adobe")
  end

  it "prefills the new form from params" do
    sign_in_as user_with_role("editor", business)
    get new_business_rule_path(business, value: "ADOBE", category_id: category.id)
    expect(response.body).to include('value="ADOBE"')
  end

  it "reorders from a JSON position" do
    a = create(:rule, business: business, category: category)
    b = create(:rule, business: business, category: category)
    sign_in_as user_with_role("editor", business)
    patch move_business_rule_path(business, b), params: { position: 1 }, as: :json
    expect(response).to have_http_status(:no_content)
    expect(business.rules.ordered.to_a).to eq([b, a])
  end

  it "rejects a move without a position" do
    rule = create(:rule, business: business, category: category)
    sign_in_as user_with_role("editor", business)
    patch move_business_rule_path(business, rule), params: {}, as: :json
    expect(response).to have_http_status(:bad_request)
  end

  it "applies rules to the inbox" do
    create(:rule, business: business, value: "adobe", category: category)
    txn = create(:transaction, account: create(:account, business: business), payee: "Adobe")
    sign_in_as user_with_role("editor", business)
    post apply_business_rules_path(business)
    expect(txn.reload.category).to eq(category)
    expect(flash[:notice]).to eq("1 transaction categorized.")
  end

  it "forbids viewers from writing" do
    rule = create(:rule, business: business, category: category)
    sign_in_as user_with_role("viewer", business)
    post business_rules_path(business), params: { rule: { value: "x" } }
    expect(response).to have_http_status(:forbidden)
    patch move_business_rule_path(business, rule), params: { position: 1 }, as: :json
    expect(response).to have_http_status(:forbidden)
    post apply_business_rules_path(business)
    expect(response).to have_http_status(:forbidden)
    delete business_rule_path(business, rule)
    expect(response).to have_http_status(:forbidden)
  end
end
