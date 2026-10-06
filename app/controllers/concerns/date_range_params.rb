module DateRangeParams
  extend ActiveSupport::Concern

  included do
    helper_method :date_range
  end

  private

  def date_range
    @date_range ||= begin
      from = parse_date(params[:from]) || Date.current.beginning_of_year
      to = parse_date(params[:to]) || Date.current
      if from > to
        flash.now[:notice] = "Start date was after end date — swapped."
        to..from
      else
        from..to
      end
    end
  end

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end
end
