class BusinessProvisioner
  def self.call(business, owner:)
    ApplicationRecord.transaction do
      business.save!
      business.memberships.create!(user: owner, role: "owner")
      business.accounts.create!(name: "Cash", source: "manual", kind: "cash")
      CategoryTemplate.apply_to(business)
    end
    business
  end
end
