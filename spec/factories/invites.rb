FactoryBot.define do
  factory :invite do
    association :created_by, factory: [ :user, :household_owner ]
    transient do
      business { association :business }
      role { "viewer" }
    end
    after(:build) { |invite, ctx| invite.grant_roles = { ctx.business.id.to_s => ctx.role } }
  end
end
