# "Remove from household": drops every membership, ends every session, revokes invites they created, and blocks sign-in.
# The user row stays so audit events keep their actor.
class User::Deactivation
  Result = Data.define(:error) do
    def ok? = error.nil?
  end

  def self.call(user, by:) = new(user, by).call

  def initialize(user, actor)
    @user = user
    @actor = actor
  end

  def call
    ApplicationRecord.transaction do
      Business.where(id: @user.memberships.select(:business_id)).order(:id).each(&:lock!)
      error = refusal
      next Result.new(error:) if error

      Invite.usable.where(created_by: @user).update_all(expires_at: Time.current)
      @user.memberships.each(&:destroy!)
      @user.sessions.destroy_all
      @user.update!(deactivated_at: Time.current)
      Audit.note("Removed #{@user.name} from the household", record: @user)
      Result.new(error: nil)
    end
  end

  private

  def refusal
    return "You can't remove yourself." if @user == @actor
    return "#{@user.name} has already been removed." if @user.deactivated?
    return "Household owners can't be removed." if @user.household_owner?

    books = @user.memberships.owner.includes(:business).select(&:last_owner?).map(&:business)
    "#{@user.name} is the last owner of #{books.map(&:name).to_sentence}. Make someone else an owner first." if books.any?
  end
end
