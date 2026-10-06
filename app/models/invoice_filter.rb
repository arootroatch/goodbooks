class InvoiceFilter
  PER_PAGE = 50
  STATUSES = { "open" => "Open", "overdue" => "Overdue", "paid" => "Paid", "draft" => "Draft", "void" => "Void" }.freeze

  attr_reader :page

  def initialize(scope, params, today: Date.current)
    @scope = scope
    @params = params.to_h.symbolize_keys
    @today = today
    @page = [ [ @params[:page].to_i, 1 ].max, 10_000 ].min
  end

  def results = ordered.limit(PER_PAGE).offset((page - 1) * PER_PAGE)
  def all = ordered
  def next_page? = filtered.count > page * PER_PAGE
  def params = @params.slice(:status, :client_id, :from, :to)
  def outstanding_cents = open_invoices.sum(&:outstanding_cents)
  def overdue_cents = open_invoices.select { _1.overdue?(@today) }.sum(&:outstanding_cents)

  private

  def ordered = filtered.includes(:client, :business, :payments).order(issue_date: :desc, id: :desc)

  def open_invoices
    @open_invoices ||= filtered.sent.includes(:payments).to_a
  end

  def filtered
    relation =
      case @params[:status]
      when "open" then @scope.sent
      when "overdue" then @scope.sent.where("invoices.due_date < ?", @today)
      when "paid", "draft", "void" then @scope.where(status: @params[:status])
      else @scope
      end
    relation = relation.where(client_id: @params[:client_id]) if @params[:client_id].present?
    relation = relation.where(issue_date: date(:from)..) if date(:from)
    relation = relation.where(issue_date: ..date(:to)) if date(:to)
    relation
  end

  def date(key)
    Date.iso8601(@params[key].to_s)
  rescue Date::Error
    nil
  end
end
