class MembershipsController < ApplicationController
  include BusinessScoped

  LAST_OWNER = "Every book needs at least one owner."
  HOUSEHOLD_OWNER = "The household owner's access can only be changed by the household owner."

  before_action :require_owner!
  before_action :set_member, only: %i[update destroy]

  def index
    @memberships = @business.memberships.includes(:user).order(:role)
  end

  def update
    return redirect_to(business_memberships_path(@business), alert: HOUSEHOLD_OWNER) if protected_member?

    role = params.dig(:membership, :role)
    return redirect_to(business_memberships_path(@business), alert: "Choose a valid role.") unless Membership.roles.key?(role)

    @business.with_lock do
      @member.reload
      return redirect_to(business_memberships_path(@business), alert: LAST_OWNER) if @member.last_owner? && role != "owner"

      @member.update!(role: role)
    end
    redirect_to business_memberships_path(@business), notice: "Role updated."
  end

  def destroy
    return redirect_to(business_memberships_path(@business), alert: HOUSEHOLD_OWNER, status: :see_other) if protected_member?

    @business.with_lock do
      @member.reload
      return redirect_to(business_memberships_path(@business), alert: LAST_OWNER, status: :see_other) if @member.last_owner?

      @member.destroy!
    end
    redirect_to business_memberships_path(@business), notice: "Member removed.", status: :see_other
  end

  private

  def protected_member?
    @member.user.household_owner? && @member.user != Current.user
  end

  def set_member
    @member = @business.memberships.find(params[:id])
  end
end
