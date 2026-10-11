# Invoices, clients, mileage, Schedule C, and P&L don't exist for the personal book. Include after BusinessScoped.
module BusinessKindOnly
  extend ActiveSupport::Concern

  included do
    before_action :require_business_kind!
  end

  private

  def require_business_kind!
    raise ActiveRecord::RecordNotFound if @business.personal?
  end
end
