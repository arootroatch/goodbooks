module BusinessScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_business
    helper_method :current_membership
  end

  private

  def set_business
    @business = Current.user.accessible_businesses.find(params[:business_id])
    @membership = Current.user.membership_for(@business)
  end

  def current_membership = @membership

  def require_editor!
    head :forbidden unless @membership.can_edit?
  end

  def require_owner!
    head :forbidden unless @membership.owner?
  end
end
