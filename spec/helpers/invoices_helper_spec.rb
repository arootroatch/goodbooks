require "rails_helper"

RSpec.describe InvoicesHelper do
  describe "#invoice_status_badge" do
    def badge_for(status) = Capybara.string(helper.invoice_status_badge(instance_double(Invoice, display_status: status)))

    it "maps each status onto a design-system badge variant" do
      expect(badge_for("paid")).to have_css("span.badge.badge-pos", text: "Paid")
      expect(badge_for("overdue")).to have_css("span.badge.badge-neg", text: "Overdue")
      expect(badge_for("draft")).to have_css("span.badge.badge-muted", text: "Draft")
      expect(badge_for("void")).to have_css("span.badge.badge-muted", text: "Void")
    end

    it "uses the default accent badge for sent invoices" do
      expect(badge_for("sent").find("span")[:class]).to eq("badge")
    end
  end
end
