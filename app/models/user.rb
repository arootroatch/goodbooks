class User < ApplicationRecord
  include TwoFactor

  has_secure_password
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true
  validates :name, presence: true
  validates :password, length: { minimum: 12 }, allow_nil: true
end
