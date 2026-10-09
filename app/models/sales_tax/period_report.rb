module SalesTax
  # Figures and status for one filing period (spec §5.2). Pure: structs in, numbers out.
  class PeriodReport
    Deposit = Data.define(:posted_on, :treatment, :gross_cents, :total_tax_cents, :source) do
      def initialize(posted_on:, treatment:, gross_cents:, total_tax_cents:, source: nil) = super
    end

    Remittance = Data.define(:posted_on, :amount_cents, :period_starts_on, :source) do
      def initialize(posted_on:, amount_cents:, period_starts_on:, source: nil) = super
    end

    attr_reader :period, :filing, :deposits, :remittances

    def initialize(period:, deposits:, remittances:, filing:, today:)
      @period = period
      @filing = filing
      @today = today
      dates = period.starts_on..period.ends_on
      @deposits = deposits.select { dates.cover?(_1.posted_on) }.sort_by(&:posted_on)
      @remittances = remittances.select { _1.period_starts_on == period.starts_on }.sort_by(&:posted_on)
    end

    def gross_sales_cents = deposits.sum(&:gross_cents)
    def exempt_sales_cents = deposits.select { _1.treatment == "exempt" }.sum(&:gross_cents)
    def taxable_sales_cents = deposits.select { _1.treatment == "taxable" }.sum { _1.gross_cents - _1.total_tax_cents }
    def tax_collected_cents = deposits.sum(&:total_tax_cents)
    def remitted_cents = -remittances.sum(&:amount_cents)
    def balance_cents = tax_collected_cents - remitted_cents

    def filed? = !filing.nil?
    def paid? = status == "paid"

    def status
      if filed? then balance_cents <= 0 ? "paid" : "filed"
      elsif @today > period.due_on then "overdue"
      elsif @today > period.ends_on then "due"
      else "open"
      end
    end
  end
end
