# Household-owner view of every login: book access, last activity, sign-out and removal. Taxpayers live on PeopleController.
class UsersController < ApplicationController
  before_action :require_household_owner!
  before_action :set_user, except: :index

  def index
    @users = User.active.includes(memberships: :business).order(:name)
    @deactivated = User.deactivated.order(:name)
    @last_seen = Session.group(:user_id).maximum(:last_seen_at)
  end

  def sign_out
    @user.sessions.destroy_all
    if @user == Current.user
      cookies.delete(:session_id)
      return redirect_to(new_session_path, status: :see_other)
    end

    redirect_to users_path, notice: "Signed #{@user.name} out everywhere.", status: :see_other
  end

  def deactivate
    result = User::Deactivation.call(@user, by: Current.user)
    if result.ok?
      redirect_to users_path, notice: "#{@user.name} removed from the household.", status: :see_other
    else
      redirect_to users_path, alert: result.error, status: :see_other
    end
  end

  def reactivate
    @user.update!(deactivated_at: nil)
    Audit.note("Reactivated #{@user.name}", record: @user)
    redirect_to users_path, notice: "#{@user.name} reactivated. Send an invite to give them access to books.", status: :see_other
  end

  private

  def set_user
    @user = User.find(params[:id])
  end
end
