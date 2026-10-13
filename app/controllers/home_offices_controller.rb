class HomeOfficesController < ApplicationController
  include BusinessScoped
  include BusinessKindOnly
  include TaxYearParam

  before_action :require_home_office_editor!
  before_action { @home_office = @business.home_offices.find_or_initialize_by(year: tax_year_from(params[:year])) }

  def edit
  end

  def update
    if @home_office.update(params.expect(home_office: [ :calculation, :office_sqft, :home_sqft, *HomeOffice::COSTS ]))
      redirect_to business_schedule_c_path(@business, year: @home_office.year), notice: "Home office saved."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def require_home_office_editor!
    head :forbidden unless Current.user.can_edit_home_office?(@business)
  end
end
