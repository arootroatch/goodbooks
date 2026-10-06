class InvitesController < ApplicationController
  before_action :require_inviter!

  def index
    scope = Current.user.household_owner? ? Invite.all : Invite.where(created_by: Current.user)
    @invites = scope.includes(:accepted_by, grants: :business).order(created_at: :desc)
  end

  def new
    @invite = Invite.new
    @grantable = grantable_businesses
  end

  def create
    attrs = params[:invite].is_a?(ActionController::Parameters) ? params[:invite] : ActionController::Parameters.new
    roles = attrs[:grant_roles]
    @invite = Invite.new(created_by: Current.user, email: attrs[:email].to_s.presence)
    @invite.grant_roles = roles.respond_to?(:to_unsafe_h) ? roles.to_unsafe_h : {}
    if @invite.save
      @join_url = join_url(token: @invite.token)
      render :show, status: :created
    else
      @grantable = grantable_businesses
      render :new, status: :unprocessable_content
    end
  rescue ActiveRecord::RecordNotFound
    head :unprocessable_content
  end

  def destroy
    scope = Current.user.household_owner? ? Invite.all : Invite.where(created_by: Current.user)
    scope.find(params[:id]).update!(expires_at: Time.current)
    redirect_to invites_path, notice: "Invite revoked.", status: :see_other
  end

  private

  def require_inviter!
    head :forbidden unless Current.user.household_owner? || Current.user.memberships.owner.exists?
  end

  def grantable_businesses
    return Business.active.order(:name) if Current.user.household_owner?

    Business.active.where(id: Current.user.memberships.owner.select(:business_id)).order(:name)
  end
end
