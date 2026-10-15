class BusinessProvisioner
  def self.call(business, owner:)
    Audit.summarize do |summary|
      ApplicationRecord.transaction do
        business.save!
        business.memberships.create!(user: owner, role: "owner")
        business.accounts.create!(name: "Cash", source: "manual", kind: "cash")
        CategoryTemplate.apply_to(business)
      end
      summary.record = summary.business = business
      summary.text = "Created book #{business.name}"
    end
    business
  end
end
