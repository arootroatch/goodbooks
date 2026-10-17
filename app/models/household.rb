class Household < ApplicationRecord
  include Audited
  audited label: -> { name }
  has_many :people, dependent: :destroy
  has_many :businesses, dependent: :destroy
  has_many :plaid_items, dependent: :destroy
  has_many :tax_years, dependent: :destroy

  DEFAULT_IRS_PAYMENT_URL = "https://www.irs.gov/payments/direct-pay".freeze

  validates :name, presence: true
  validates :irs_payment_url, format: { with: %r{\Ahttps://[a-z0-9.-]+\.[a-z]{2,}(/\S*)?\z}i, message: "must be an https:// web address" }

  def self.instance = first!

  def personal_book = businesses.personal.first
end
