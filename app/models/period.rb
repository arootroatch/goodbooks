# A calendar month, quarter, or year the overview reports on.
class Period
  KINDS = %w[month quarter year].freeze
  Bucket = Data.define(:label, :range)

  attr_reader :kind, :range, :today

  def self.from_params(params, today: Date.current)
    kind = KINDS.include?(params[:period]) ? params[:period] : "year"
    on = begin
      Date.iso8601(params[:on].to_s)
    rescue ArgumentError
      today
    end
    new(kind, on, today:)
  end

  def initialize(kind, date, today: Date.current)
    @kind = kind
    @today = today
    @range = date.public_send(:"beginning_of_#{kind}")..date.public_send(:"end_of_#{kind}")
  end

  def label
    case kind
    when "month" then range.first.strftime("%B %Y")
    when "quarter" then "Q#{(range.first.month + 2) / 3} #{range.first.year}"
    else range.first.year.to_s
    end
  end

  def dates = "#{range.first.strftime('%b %-d')} – #{range.last.strftime('%b %-d, %Y')}"

  def previous = Period.new(kind, range.first - 1, today:)
  def next = Period.new(kind, range.last + 1, today:)
  def next? = range.last < today

  def switch_to(other_kind) = Period.new(other_kind, range.cover?(today) ? today : range.first, today:)

  def to_params = { period: kind, on: range.first.iso8601 }

  def buckets
    bucket_unit == "week" ? weeks : months
  end

  def bucket_unit = kind == "month" ? "week" : "month"

  def bucket_in_progress = buckets.index { _1.range.cover?(today) }

  private

  def weeks
    range.first.step(range.last).slice_when { |_, day| day.monday? }
      .map { Bucket.new(label: _1.first.strftime("%b %-d"), range: _1.first.._1.last) }
  end

  def months
    range.first.step(range.last).select { _1.day == 1 }
      .map { Bucket.new(label: Date::ABBR_MONTHNAMES[_1.month], range: _1.._1.end_of_month) }
  end
end
