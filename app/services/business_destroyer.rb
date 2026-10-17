# Permanently deletes a business-kind book and everything in it, in one transaction, writing one audit summary.
# Refuses the personal book, books with invoices or clients (records to delete by hand), and books Plaid still feeds.
class BusinessDestroyer
  Result = Data.define(:errors) do
    def ok? = errors.empty?
  end

  def self.call(business) = new(business).call

  def initialize(business)
    @business = business
  end

  def call
    errors = refusals
    return Result.new(errors:) if errors.any?

    Audit.summarize(business: @business.id) do |summary|
      ApplicationRecord.transaction do
        # Transactions go first: accounts, goals, rules and categories all refuse while rows point at them.
        Transaction.for_businesses(@business.id).find_each(&:destroy!)
        drop_invite_grants
        @business.destroy!
      end
      summary.text = "Deleted book #{@business.name}"
    end
    Result.new(errors: [])
  end

  private

  def refusals
    if @business.personal? then [ "The personal book can't be deleted." ]
    elsif @business.clients.exists? || @business.invoices.exists? then [ "Delete this business's invoices and clients first." ]
    elsif @business.accounts.where.not(plaid_item_id: nil).exists? then [ "Unlink this business's bank accounts from Plaid first." ]
    else []
    end
  end

  def drop_invite_grants
    invite_ids = InviteGrant.where(business: @business).pluck(:invite_id)
    InviteGrant.where(business: @business).destroy_all
    Invite.where(id: invite_ids, accepted_by_id: nil).where.missing(:grants).destroy_all
  end
end
