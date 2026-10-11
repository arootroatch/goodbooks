class TithesController < ApplicationController
  include BusinessScoped
  include PersonalOnly

  before_action :require_owner!, only: :update

  def show
    @ledger = Tithe.ledger_for(@business)
    respond_to do |format|
      format.html
      format.csv do
        if @ledger
          send_data Reports::TitheCsv.generate(@ledger), filename: "tithe-#{Date.current}.csv", type: "text/csv"
        else
          head :not_found
        end
      end
    end
  end

  def update
    raw = params.expect(business: %i[tithe_start_on])[:tithe_start_on].to_s
    start_on = parse_iso_date(raw)
    if raw.present? && start_on.nil?
      redirect_to business_tithe_path(@business), alert: "Tithe start date is not a valid date."
    elsif @business.update(tithe_start_on: start_on)
      redirect_to business_tithe_path(@business), notice: start_on ? "Tithe start date saved." : "Tithe tracking turned off."
    else
      redirect_to business_tithe_path(@business), alert: @business.errors.full_messages.to_sentence
    end
  end

  private

  def parse_iso_date(value)
    Date.iso8601(value)
  rescue ArgumentError
    nil
  end
end
