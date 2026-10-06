class MileageEntriesController < ApplicationController
  include BusinessScoped

  PERMITTED = %i[driven_on purpose from_location to_location miles round_trip].freeze

  before_action :require_editor!, except: :index
  before_action :set_entry, only: %i[edit update destroy]

  def index
    @year = year_param
    @entries = @business.mileage_entries.where(driven_on: Date.new(@year).all_year).order(:driven_on)
    @total_tenths = @entries.sum(&:effective_miles_tenths)
    @rate = TaxParameters.for_year(@year)
    @deduction_cents = @rate && MileageDeduction.cents(miles_tenths: @total_tenths, rate_tenth_cents: @rate.standard_mileage_rate_tenth_cents)
  end

  def new
    @entry = @business.mileage_entries.new(driven_on: Date.current)
  end

  def create
    @entry = @business.mileage_entries.new(params.expect(mileage_entry: PERMITTED))
    if @entry.save
      redirect_to business_mileage_entries_path(@business, year: @entry.driven_on.year), notice: "Trip logged."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @entry.update(params.expect(mileage_entry: PERMITTED))
      redirect_to business_mileage_entries_path(@business, year: @entry.driven_on.year), notice: "Trip updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @entry.destroy!
    redirect_to business_mileage_entries_path(@business, year: @entry.driven_on.year), notice: "Trip deleted.", status: :see_other
  end

  private

  def set_entry
    @entry = @business.mileage_entries.find(params[:id])
  end
end
