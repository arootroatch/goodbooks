module Invoices
  # Sent invoices that still have money owed, split into overdue and not yet due, oldest due date first.
  class OpenSummary
    Group = Data.define(:invoices) do
      def total_cents = invoices.sum(&:outstanding_cents)
      def count = invoices.size
    end

    attr_reader :overdue, :upcoming, :today

    def self.for(scope, today: Date.current)
      open = scope.sent.includes(:client, :business, :payments).order(:due_date, :id).select { _1.outstanding_cents.positive? }
      overdue, upcoming = open.partition { _1.overdue?(today) }
      new(overdue: Group.new(overdue), upcoming: Group.new(upcoming), today:)
    end

    def initialize(overdue:, upcoming:, today:)
      @overdue = overdue
      @upcoming = upcoming
      @today = today
    end

    def outstanding_cents = overdue.total_cents + upcoming.total_cents
  end
end
