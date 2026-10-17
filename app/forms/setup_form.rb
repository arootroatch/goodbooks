class SetupForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :household_name, :string
  attribute :name, :string
  attribute :email_address, :string
  attribute :password, :string
  attribute :password_confirmation, :string
  attribute :spouse_name, :string

  validates :household_name, :name, presence: true

  def save
    return unless valid?

    ApplicationRecord.transaction do
      return already_completed if Household.exists?

      user = User.create!(name:, email_address:, password:, password_confirmation:, household_owner: true)
      Audit.as(user) do
        household = Household.create!(name: household_name)
        household.people.create!(name:, user:)
        household.people.create!(name: spouse_name) if spouse_name.present?
      end
      user
    end
  rescue ActiveRecord::RecordInvalid => e
    e.record.errors.each { |error| errors.add(error.attribute, error.message) }
    nil
  rescue ActiveRecord::RecordNotUnique
    already_completed
  end

  private

  def already_completed
    errors.add(:base, "Setup has already been completed.")
    nil
  end
end
