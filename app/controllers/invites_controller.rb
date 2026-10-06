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
    @invite = Invite.new(created_by: Current.user, email: params.dig(:invite, :email))
    @invite.grant_roles = params.dig(:invite, :grant_roles)&.to_unsafe_h || {}
    if @invite.save
      @join_url = join_url(@invite.token)
      render :show, status: :created
    else
      @grantable = grantable_businesses
      render :new, status: :unprocessable_content
    end
  rescue ActiveRecord::RecordNotFound
    head :unprocessable_content
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
