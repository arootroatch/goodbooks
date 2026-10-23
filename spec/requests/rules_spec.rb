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

  it "takes the amount range in whole dollars against a fixed .00" do
    sign_in_as user_with_role("editor", business)
    get new_business_rule_path(business)
    form = Capybara.string(response.body)
    expect(form).to have_css(".dollar-field", text: "$", count: 2)
    expect(form.find(".dollar-field", match: :first)).to have_field("rule[amount_min]", with: "")
      .and have_css(".dollar-field-cents[aria-hidden=true]", text: ".00")
    expect(form).to have_text("money in or out; leave blank for no limit")
    post business_rules_path(business), params: { rule: {
      field: "payee", operator: "contains", value: "adobe", outcome: "categorize", category_id: category.id, amount_min: "10", amount_max: "25.50"
    } }
    rule = business.rules.last
    expect(rule).to have_attributes(amount_min_cents: 1_000, amount_max_cents: 2_550)

    get edit_business_rule_path(business, rule)
    min, max = Capybara.string(response.body).all(".dollar-field").to_a
    expect(min).to have_field("rule[amount_min]", with: "10").and have_css(".dollar-field-cents")
    expect(max).to have_field("rule[amount_max]", with: "25.50").and have_no_css(".dollar-field-cents")

    patch business_rule_path(business, rule), params: { rule: { amount_min: "30" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(Capybara.string(response.body)).to have_css(".dollar-field.dollar-field-error", text: "$").and have_no_css(".field_with_errors")
  end

  it "marks rules whose category is archived as inactive" do
    create(:rule, business: business, value: "adobe", category: category)
    category.update!(archived_at: Time.current)
    sign_in_as user_with_role("viewer", business)
    get business_rules_path(business)
    expect(response.body).to include("(category archived — rule inactive)")
  end

  it "does not mark rules with active categories" do
    create(:rule, business: business, value: "adobe", category: category)
    sign_in_as user_with_role("viewer", business)
    get business_rules_path(business)
    expect(response.body).not_to include("rule inactive")
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
    expect(business.rules.ordered.to_a).to eq([ b, a ])
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
