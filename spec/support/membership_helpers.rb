module MembershipHelpers
  def user_with_role(role, business, **attrs)
    create(:user, **attrs).tap { |user| create(:membership, user: user, business: business, role: role) }
  end
end

RSpec.configure do |config|
  config.include MembershipHelpers
end
