class Business < ApplicationRecord
  belongs_to :household
  belongs_to :person
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :accounts, dependent: :destroy
  has_many :rules, dependent: :destroy
  has_many :categories, dependent: :destroy
  has_many :transactions, through: :accounts

  scope :active, -> { where(archived_at: nil) }

  validates :name, presence: true
  validate :person_in_household

  private

  def person_in_household
    errors.add(:person, "must belong to this household") if person && person.household_id != household_id
  end
end
