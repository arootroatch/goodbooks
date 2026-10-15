class HouseholdsController < ApplicationController
  before_action :require_household_owner!
  before_action { @household = Household.instance }

  def edit
  end

  def update
    if @household.update(params.expect(household: %i[name irs_payment_url]))
      redirect_to edit_household_path, notice: "Household saved."
    else
      render :edit, status: :unprocessable_content
    end
  end
end
