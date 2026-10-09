class Business < ApplicationRecord
  belongs_to :household
  belongs_to :person, optional: true
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :accounts, dependent: :destroy
  has_many :rules, dependent: :destroy
  has_many :categories, dependent: :destroy
  has_many :mileage_entries, dependent: :destroy
  has_many :clients, dependent: :restrict_with_error
  has_many :invoices, dependent: :restrict_with_error
  has_many :transactions, through: :accounts
  has_one :sales_tax_profile, dependent: :destroy
  has_many :sales_tax_filings, dependent: :destroy

  enum :kind, { business: "business", personal: "personal" }, validate: true, scopes: false

  scope :active, -> { where(archived_at: nil) }
  scope :business_kind, -> { where(kind: "business") }
  scope :personal, -> { where(kind: "personal") }

  validates :name, presence: true
  validates :person, presence: true, if: :business?
  validates :kind, uniqueness: { scope: :household_id, message: "already exists for this household" }, if: :personal?
  validate :person_in_household
  validate :personal_has_no_person
  validate :tithe_start_on_allowed
  validate :personal_not_archived

  TITHE_START_FLOOR = Date.new(2000, 1, 1)

  def collects_sales_tax? = business? && sales_tax_profile&.active? == true

  private

  def person_in_household
    errors.add(:person, "must belong to this household") if person && person.household_id != household_id
  end

  def personal_has_no_person
    errors.add(:person, "must be blank for the personal book") if personal? && person_id.present?
  end

  def tithe_start_on_allowed
    return if tithe_start_on.nil?

    if business? then errors.add(:tithe_start_on, "is only for the personal book")
    elsif tithe_start_on > Date.current then errors.add(:tithe_start_on, "can't be in the future")
    elsif tithe_start_on < TITHE_START_FLOOR then errors.add(:tithe_start_on, "can't be before 2000-01-01")
    end
  end

  def personal_not_archived
    errors.add(:base, "The personal book can't be archived") if personal? && archived_at.present?
  end
end
