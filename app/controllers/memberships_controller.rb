class MembershipsController < ApplicationController
  include BusinessScoped

  LAST_OWNER = "A business needs at least one owner."

  before_action :require_owner!
  before_action :set_member, only: %i[update destroy]

  def index
    @memberships = @business.memberships.includes(:user).order(:role)
  end

  def update
    role = params.expect(membership: [:role])[:role]
    return redirect_to(business_memberships_path(@business), alert: LAST_OWNER) if @member.last_owner? && role != "owner"

    @member.update!(role: role)
    redirect_to business_memberships_path(@business), notice: "Role updated."
  end

  def destroy
    return redirect_to(business_memberships_path(@business), alert: LAST_OWNER, status: :see_other) if @member.last_owner?

    @member.destroy!
    redirect_to business_memberships_path(@business), notice: "Member removed.", status: :see_other
  end

  private

  def set_member
    @member = @business.memberships.find(params[:id])
  end
end
