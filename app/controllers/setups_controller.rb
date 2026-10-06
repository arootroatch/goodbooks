class SetupsController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :require_household
  before_action { head :not_found if Household.exists? }

  def new
    @setup = SetupForm.new
  end

  def create
    @setup = SetupForm.new(params.expect(setup: %i[household_name name email_address password password_confirmation spouse_name]))
    if (user = @setup.save)
      begin_two_factor(user)
    elsif Household.exists?
      head :not_found
    else
      render :new, status: :unprocessable_content
    end
  end
end
