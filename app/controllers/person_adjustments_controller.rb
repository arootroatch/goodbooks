class PersonAdjustmentsController < ApplicationController
  include TaxYearParam

  household_page
  before_action { @person = Household.instance.people.find(params[:person_id]) }
  before_action :require_adjustment_editor!
  before_action { @adjustment = @person.person_adjustments.find_or_initialize_by(year: tax_year_from(params[:year])) }

  def edit
  end

  def update
    if @adjustment.update(params.expect(person_adjustment: %i[se_health_insurance retirement_contribution retirement_plan]))
      redirect_to tax_year_path(@adjustment.year), notice: "Adjustments saved."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def require_adjustment_editor!
    return if Current.user.can_edit_adjustments?(@person)

    head(Current.user.can_view_household? ? :forbidden : :not_found)
  end
end
