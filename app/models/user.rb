class User < ApplicationRecord
  include TwoFactor

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_one :person, dependent: :nullify

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true
  validates :name, presence: true
  validates :password, length: { minimum: 12 }, allow_nil: true

  def accessible_businesses
    Business.where(id: memberships.select(:business_id))
  end

  def membership_for(business)
    memberships.find_by(business: business)
  end

  def can_view_household?
    household_owner? || (memberships.exists? && Business.where.not(id: memberships.select(:business_id)).none?)
  end
end
