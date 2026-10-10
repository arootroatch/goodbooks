require "rails_helper"

RSpec.describe "Invoice filters", js: true do
  let!(:business) { create(:business) }

  before do
    create(:invoice, business:, number: "INV-OLD", amount_cents: 80_000, due_date: Date.current - 10)
    create(:invoice, business:, number: "INV-NEW", amount_cents: 50_000, due_date: Date.current + 20)
  end

  shared_examples "live invoice filters" do
    it "filters on change without a Filter button and keeps the summary and CSV link in step" do
      expect(page).to have_no_button("Filter")
      select "Overdue", from: "status"

      expect(page).to have_no_text("INV-NEW")
      expect(page).to have_text("INV-OLD")
      expect(page).to have_current_path(/status=overdue/)
      expect(page).to have_text("Outstanding $800.00")
      expect(page).to have_link("Download CSV", href: /status=overdue/)
    end
  end

  context "in a business" do
    before do
      system_sign_in_as user_with_role("viewer", business)
      visit business_invoices_path(business)
    end

    include_examples "live invoice filters"
  end

  context "across the household" do
    before do
      system_sign_in_as create(:user, :household_owner)
      visit household_invoices_path
    end

    include_examples "live invoice filters"
  end
end
