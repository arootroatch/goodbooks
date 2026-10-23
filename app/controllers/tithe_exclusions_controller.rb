# Leaves one transaction out of the tithe (create) or counts it again (destroy). It still counts everywhere else.
class TitheExclusionsController < ApplicationController
  include BusinessScoped
  include PersonalOnly

  before_action :require_editor!

  def create = set_excluded(true)

  def destroy = set_excluded(false)

  private

  def set_excluded(value)
    transaction = Transaction.for_businesses(@business.id).find(params[:transaction_id])
    week = Tithe::Ledger.week_start(transaction.posted_on).iso8601
    flash[:alert] = transaction.errors.full_messages.to_sentence unless transaction.update(tithe_excluded: value)
    redirect_to business_tithe_path(@business, week: week, anchor: "week-#{week}"), status: :see_other
  end
end
