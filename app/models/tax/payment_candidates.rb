module Tax
  # Bank transactions a household owner can record as an estimated payment.
  module PaymentCandidates
    LIMIT = 50
    IRS_FIRST_SQL = "CASE WHEN transactions.payee LIKE '%IRS%' OR transactions.payee LIKE '%USATAXPYMT%' " \
                    "OR transactions.payee LIKE '%EFTPS%' THEN 0 ELSE 1 END".freeze

    module_function

    def scope_for(user) = Transaction.for_businesses(user.accessible_businesses.select(:id))

    def for(user:, year:, query: nil)
      scope = scope_for(user).where("transactions.amount_cents < 0").where(posted_on: Date.new(year, 1, 1)..Date.new(year + 1, 1, 31))
        .where.missing(:estimated_payment)
      scope = scope.where("transactions.payee LIKE ? ESCAPE '\\'", "%#{Transaction.sanitize_sql_like(query.strip)}%") if query.present?
      scope.includes(account: :business).order(Arel.sql(IRS_FIRST_SQL)).order(posted_on: :desc, id: :desc).limit(LIMIT)
    end
  end
end
