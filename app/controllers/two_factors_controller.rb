class TwoFactorsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Try again later." }
  before_action :require_pending_user

  def new
  end

  def create
    if @user.verify_otp(params[:code]) || @user.consume_recovery_code(params[:code])
      complete_two_factor(@user)
      redirect_to after_authentication_url
    else
      flash.now[:alert] = "That code didn't work."
      render :new, status: :unprocessable_content
    end
  end

  private

  def require_pending_user
    @user = pending_user
    redirect_to new_session_path unless @user&.otp_enabled?
  end
end
