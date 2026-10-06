class Person < ApplicationRecord
  MAX_PER_HOUSEHOLD = 2

  belongs_to :household
  belongs_to :user, optional: true
  has_many :businesses, dependent: :restrict_with_error

  validates :name, presence: true
  validates :user_id, uniqueness: true, allow_nil: true
  validate :household_has_room, on: :create

  private

  def household_has_room
    return unless household && household.people.count >= MAX_PER_HOUSEHOLD

    errors.add(:base, "A household has at most two people")
  end
end
