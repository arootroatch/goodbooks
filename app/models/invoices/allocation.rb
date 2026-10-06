module Invoices
  module Allocation
    Result = Data.define(:amount_cents, :error) do
      def ok? = error.nil?
    end

    def self.call(invoice_amount_cents:, invoice_paid_cents:, deposit_amount_cents:, deposit_allocated_cents:, requested_cents: nil)
      outstanding = invoice_amount_cents - invoice_paid_cents
      unallocated = deposit_amount_cents - deposit_allocated_cents
      return failure("This invoice is already fully paid.") unless outstanding.positive?
      return failure("This deposit is already fully allocated.") unless unallocated.positive?
      return success([ outstanding, unallocated ].min) if requested_cents.nil?
      return failure("Amount must be greater than zero.") unless requested_cents.positive?
      return failure("Amount can't exceed the invoice's outstanding #{Money.new(outstanding)}.") if requested_cents > outstanding
      return failure("Amount can't exceed the deposit's unallocated #{Money.new(unallocated)}.") if requested_cents > unallocated

      success(requested_cents)
    end

    def self.success(cents) = Result.new(amount_cents: cents, error: nil)
    def self.failure(message) = Result.new(amount_cents: nil, error: message)
    private_class_method :success, :failure
  end
end
