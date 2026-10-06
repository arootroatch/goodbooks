class TwoFactorSetupsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Try again later." }
  rate_limit to: 10, within: 3.minutes, by: -> { session[:pending_user_id].to_s }, only: :create, name: "per_user",
             with: -> { redirect_to new_session_path, alert: "Try again later." }
  before_action :require_pending_user

  def new
    @user.generate_otp_secret! if @user.otp_secret.blank?
    @qr_svg = RQRCode::QRCode.new(@user.otp_provisioning_uri).as_svg(module_size: 4, use_path: true)
  end

  def create
    if @user.verify_otp(params[:code])
      @recovery_codes = @user.enable_otp!
      complete_two_factor(@user)
      render :recovery_codes
    else
      redirect_to new_two_factor_setup_path, alert: "That code didn't work. Try again."
    end
  end

  private

  def require_pending_user
    @user = pending_user
    redirect_to new_session_path if @user.nil? || @user.otp_enabled?
  end
end
