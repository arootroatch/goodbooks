module BusinessKindValidation
  extend ActiveSupport::Concern

  included do
    validate :business_kind_only
  end

  private

  def business_kind_only
    errors.add(:business, "must be a business, not the personal book") if business&.personal?
  end
end
