class Household < ApplicationRecord
  has_many :people, dependent: :destroy
  has_many :businesses, dependent: :destroy
  has_many :plaid_items, dependent: :destroy

  validates :name, presence: true

  def self.instance = first!

  def personal_book = businesses.personal.first
end
