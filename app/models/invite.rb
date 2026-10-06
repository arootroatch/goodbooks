class Invite < ApplicationRecord
  TTL = 7.days

  class AlreadyUsed < StandardError; end

  belongs_to :created_by, class_name: "User"
  belongs_to :accepted_by, class_name: "User", optional: true
  has_many :grants, class_name: "InviteGrant", dependent: :destroy, inverse_of: :invite

  attr_reader :token

  scope :usable, -> { where(accepted_at: nil).where("expires_at > ?", Time.current) }

  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validate :has_grants
  validate :creator_may_grant

  before_validation :generate_token, on: :create

  def self.digest(token) = Digest::SHA256.hexdigest(token.to_s)

  def self.find_usable(token) = usable.find_by(token_digest: digest(token))

  def grant_roles=(roles)
    roles.to_h.each do |business_id, role|
      next if role.blank?

      grants.build(business: Business.find(business_id), role: role)
    end
  end

  def accept!(user)
    ApplicationRecord.transaction do
      raise AlreadyUsed, "This invite has already been used or has expired." unless creator_still_authorized?

      claimed = Invite.usable.where(id: id).update_all(accepted_at: Time.current, accepted_by_id: user.id)
      raise AlreadyUsed, "This invite has already been used or has expired." if claimed.zero?

      grants.includes(:business).each do |grant|
        membership = user.memberships.find_or_initialize_by(business: grant.business)
        if membership.new_record? || Membership::RANK[grant.role] > Membership::RANK[membership.role]
          membership.role = grant.role
        end
        membership.save!
      end
    end
    reload
  end

  private

  def creator_still_authorized?
    created_by.household_owner? || grants.all? { |grant| created_by.membership_for(grant.business)&.owner? }
  end

  def generate_token
    @token = SecureRandom.urlsafe_base64(32)
    self.token_digest = self.class.digest(@token)
    self.expires_at ||= TTL.from_now
  end

  def has_grants
    errors.add(:base, "Grant access to at least one business") if grants.empty?
  end

  def creator_may_grant
    return if created_by.nil? || created_by.household_owner?
    return if grants.all? { |grant| created_by.membership_for(grant.business)&.owner? }

    errors.add(:base, "You can only grant access to businesses you own")
  end
end
