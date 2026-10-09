class TransactionFilter
  PER_PAGE = 50

  attr_reader :page

  def initialize(scope, params)
    @scope = scope
    @params = params.to_h.symbolize_keys
    @page = [ [ @params[:page].to_i, 1 ].max, 10_000 ].min
  end

  def results
    filtered.order(posted_on: :desc, id: :desc).limit(self.class::PER_PAGE).offset((page - 1) * self.class::PER_PAGE)
  end

  def next_page?
    filtered.count > page * self.class::PER_PAGE
  end

  def params = @params.slice(:from, :to, :account_id, :category_id, :status, :q)

  private

  def filtered
    relation = @scope
    relation = relation.where(posted_on: date(:from)..) if date(:from)
    relation = relation.where(posted_on: ..date(:to)) if date(:to)
    relation = relation.where(account_id: @params[:account_id]) if @params[:account_id].present?
    relation = relation.where(category_id: @params[:category_id]) if @params[:category_id].present?
    relation = relation.inbox if @params[:status] == "inbox"
    relation = relation.needing_sales_tax if @params[:status] == "needs_tax"
    if @params[:q].present?
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@params[:q])}%"
      relation = relation.where("transactions.payee LIKE :p ESCAPE '\\' OR transactions.memo LIKE :p ESCAPE '\\'", p: pattern)
    end
    relation
  end

  def date(key)
    Date.iso8601(@params[key].to_s)
  rescue Date::Error
    nil
  end
end
