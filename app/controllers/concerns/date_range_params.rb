module DateRangeParams
  extend ActiveSupport::Concern

  included do
    helper_method :date_range
  end

  private

  def date_range
    @date_range ||= (parse_date(params[:from]) || Date.current.beginning_of_year)..(parse_date(params[:to]) || Date.current)
  end

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end
end
