class AuditEventsController < ApplicationController
  include DateRangeParams

  PER_PAGE = 50

  before_action :require_household_owner!

  def index
    scope = AuditEvent.filtered(**filters, range: (date_range unless params[:auditable_id].present?))
    @events = page(scope)
    @users = User.order(:name)
    @books = Business.order(:name)
  end

  private

  def filters
    { user_id: params[:user_id].presence, auditable_type: params[:auditable_type].presence_in(Audit::MODELS),
      auditable_id: params[:auditable_id].presence, business_id: params[:business_id].presence }
  end

  # Keyset paging on id, which grows with created_at because events are append-only.
  def page(scope)
    rows = if params[:after].present?
      scope.where("audit_events.id > ?", params[:after].to_i).order(id: :asc).limit(PER_PAGE).to_a.reverse
    else
      newest = scope.order(id: :desc)
      newest = newest.where("audit_events.id < ?", params[:before].to_i) if params[:before].present?
      newest.limit(PER_PAGE).to_a
    end
    @older_id = rows.last.id if rows.any? && scope.where("audit_events.id < ?", rows.last.id).exists?
    @newer_id = rows.first.id if rows.any? && scope.where("audit_events.id > ?", rows.first.id).exists?
    AuditEvent.where(id: rows.map(&:id)).includes(:user, :business).order(id: :desc).to_a
  end
end
