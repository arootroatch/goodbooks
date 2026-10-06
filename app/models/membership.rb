class Membership < ApplicationRecord
  RANK = { "viewer" => 0, "editor" => 1, "owner" => 2 }.freeze

  belongs_to :user
  belongs_to :business

  enum :role, { owner: "owner", editor: "editor", viewer: "viewer" }, validate: true

  validates :business_id, uniqueness: { scope: :user_id }

  def can_edit? = owner? || editor?
end
