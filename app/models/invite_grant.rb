class InviteGrant < ApplicationRecord
  belongs_to :invite
  belongs_to :business

  validates :role, inclusion: { in: Membership::RANK.keys }
end
