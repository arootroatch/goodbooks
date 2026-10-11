class PersonalBooksController < ApplicationController
  def create
    return head :not_found unless Current.user.household_owner?

    book = PersonalBookProvisioner.call(Household.instance)
    redirect_to business_path(book), notice: "Personal book ready."
  end
end
