class ApplicationController < ActionController::Base
  include Authentication
  include SidebarContext

  prepend_before_action :require_household

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def year_param
    year = params[:year].to_i
    (1900..2100).cover?(year) ? year : Date.current.year
  end

  def require_household
    redirect_to new_setup_path unless Household.exists?
  end

  def require_household_owner!
    head :forbidden unless Current.user.household_owner?
  end

  def require_household_access!
    head :not_found unless Current.user.can_view_household?
  end
end
