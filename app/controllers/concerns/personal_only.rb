# Tithe and spending screens exist only for the personal book. Include after BusinessScoped.
module PersonalOnly
  extend ActiveSupport::Concern

  included do
    before_action :require_personal!
  end

  private

  def require_personal!
    raise ActiveRecord::RecordNotFound unless @business.personal?
  end
end
