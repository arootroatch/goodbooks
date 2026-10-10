# Remembers the business last opened so app-wide pages keep showing its menu.
# Household pages forget it, putting the sidebar back in the household.
module SidebarContext
  extend ActiveSupport::Concern

  included do
    helper_method :sidebar_business, :sidebar_membership
  end

  class_methods do
    def household_page
      before_action { session.delete(:business_id) }
    end
  end

  private

  def remember_business(business)
    session[:business_id] = business.id
  end

  def sidebar_business
    return @business if @business&.persisted?

    @sidebar_business ||= Current.user.accessible_businesses.find_by(id: session[:business_id]) if session[:business_id]
  end

  def sidebar_membership
    @sidebar_membership ||= Current.user.membership_for(sidebar_business) if sidebar_business
  end
end
