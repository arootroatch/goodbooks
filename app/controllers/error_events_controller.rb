class ErrorEventsController < ApplicationController
  before_action :require_household_owner!

  def index
    @tab = params[:tab] == "resolved" ? "resolved" : "open"
    @error_events = (@tab == "resolved" ? ErrorEvent.resolved : ErrorEvent.unresolved).recent_first.limit(200)
  end

  def resolve = set_resolved(Time.current, "resolved")
  def reopen = set_resolved(nil, "reopened")

  private

  def set_resolved(resolved_at, verb)
    ErrorEvent.find(params[:id]).update!(resolved_at:)
    redirect_to error_events_path(tab: params[:tab]), notice: "Error #{verb}.", status: :see_other
  end
end
