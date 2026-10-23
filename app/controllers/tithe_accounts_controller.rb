# Which accounts' income counts toward the tithe. Every active account not checked is turned off.
class TitheAccountsController < ApplicationController
  include BusinessScoped
  include PersonalOnly

  before_action :require_owner!

  def update
    ids = params.fetch(:account_ids, []).then { _1.is_a?(Array) ? _1.map(&:to_s) : [] }
    Account.transaction do
      @business.accounts.active.each { _1.update!(tithable: ids.include?(_1.id.to_s)) }
    end
    redirect_to business_tithe_path(@business), notice: "Tithe accounts saved."
  end
end
