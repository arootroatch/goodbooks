class User < ApplicationRecord
  include TwoFactor

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_one :person, dependent: :nullify

  scope :active, -> { where(deactivated_at: nil) }
  scope :deactivated, -> { where.not(deactivated_at: nil) }

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true
  validates :name, presence: true
  validates :password, length: { minimum: 12 }, allow_nil: true

  def deactivated? = deactivated_at.present?

  def accessible_businesses
    Business.where(id: memberships.select(:business_id))
  end

  def membership_for(business)
    memberships.find_by(business: business)
  end

  # A household owner or the book's owner member, and only within books they belong to.
  def can_edit_home_office?(business)
    membership = membership_for(business)
    membership.present? && (household_owner? || membership.owner?)
  end

  # A household owner, or the person's own login.
  def can_edit_adjustments?(person)
    household_owner? || person.user_id == id
  end

  # Books (business or personal) this user can connect bank accounts to.
  def owned_books
    Business.active.where(id: memberships.owner.select(:business_id))
  end

  def can_view_household?
    return true if household_owner?

    businesses = Business.business_kind
    memberships.where(business: businesses).exists? && businesses.where.not(id: memberships.select(:business_id)).none?
  end
end
