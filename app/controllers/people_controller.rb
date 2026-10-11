class PeopleController < ApplicationController
  before_action :require_household_owner!
  before_action :set_person, only: %i[edit update]

  def index
    @people = Household.instance.people.includes(:user).order(:name)
  end

  def new
    @person = Household.instance.people.new
  end

  def create
    household = Household.instance
    @person = household.people.new(person_params)
    if household.with_lock { @person.save }
      PersonalBookProvisioner.sync(household)
      redirect_to people_path, notice: "Person added."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @person.update(person_params)
      PersonalBookProvisioner.sync(Household.instance)
      redirect_to people_path, notice: "Person updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_person
    @person = Household.instance.people.find(params[:id])
  end

  def person_params
    params.expect(person: %i[name user_id])
  end
end
