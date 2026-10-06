class InviteAcceptancesController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Try again later." }
  before_action :set_invite

  def show
    @user = User.new(email_address: @invite.email)
  end

  def create
    if authenticated?
      @invite.accept!(Current.user)
      redirect_to root_path, notice: "Invite accepted."
    else
      @user = User.new(params.expect(user: %i[name email_address password password_confirmation]))
      ApplicationRecord.transaction do
        @user.save!
        @invite.accept!(@user)
      end
      begin_two_factor(@user)
    end
  rescue ActiveRecord::RecordInvalid
    render :show, status: :unprocessable_content
  rescue Invite::AlreadyUsed
    render :invalid, status: :not_found
  end

  private

  def set_invite
    @invite = Invite.find_usable(params[:token])
    render :invalid, status: :not_found unless @invite
  end
end
