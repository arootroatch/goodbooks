# The household home page: every business the user can see, this year to date, plus open invoices,
# the inbox, and (for household members) the personal book and tithe.
class HouseholdDashboard
  BusinessRow = Data.define(:business, :report, :overdue_cents, :outstanding_cents, :inbox_count)

  attr_reader :range, :businesses, :open_invoices, :book, :personal, :tithe, :inbox_count

  def initialize(user:, today: Date.current)
    @range = today.beginning_of_year..today
    accessible = user.accessible_businesses.active
    list = accessible.business_kind.order(:name).to_a
    ids = list.map(&:id)
    @open_invoices = Invoices::OpenSummary.for(Invoice.where(business_id: ids), today:)
    @book = accessible.personal.first
    inbox = Transaction.for_businesses(ids + [ @book&.id ].compact).inbox.group("accounts.business_id").count
    @inbox_count = inbox.values.sum
    totals = Reports::CategoryTotals.load(business_ids: ids, range:).group_by(&:business_id)
    @businesses = list.map { business_row(_1, totals.fetch(_1.id, []), inbox.fetch(_1.id, 0)) }
    return unless @book

    @personal = profit_and_loss(Reports::CategoryTotals.load(business_ids: [ @book.id ], range:), 0)
    @tithe = Tithe.ledger_for(@book, today:)
  end

  def business_net_cents = businesses.sum { _1.report.net_profit_cents }

  private

  def business_row(business, totals, inbox_count)
    open = (open_invoices.overdue.invoices + open_invoices.upcoming.invoices).select { _1.business_id == business.id }
    mileage = Reports::MileageTotals.load(business_ids: [ business.id ], range:).deduction_cents
    BusinessRow.new(business:, report: profit_and_loss(totals, mileage), inbox_count:,
                    overdue_cents: open.select { _1.overdue?(open_invoices.today) }.sum(&:outstanding_cents),
                    outstanding_cents: open.sum(&:outstanding_cents))
  end

  def profit_and_loss(totals, mileage) = Reports::ProfitAndLoss.new(category_totals: totals, mileage_deduction_cents: mileage)
end
