# A user's own sessions. Sign-in and sign-out stay in SessionsController.
class SessionsListController < ApplicationController
  def index
    @sessions = Current.user.sessions.order(last_seen_at: :desc)
  end

  def destroy
    record = Current.user.sessions.find(params[:id])
    if record == Current.session
      terminate_session
      return redirect_to(new_session_path, status: :see_other)
    end

    record.destroy!
    redirect_to session_records_path, notice: "Session revoked.", status: :see_other
  end

  def others
    Current.user.sessions.where.not(id: Current.session.id).destroy_all
    redirect_to session_records_path, notice: "Signed out of every other session.", status: :see_other
  end
end
