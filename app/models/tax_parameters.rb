class TaxParameters < ApplicationRecord
  include MoneyAttribute
  include PercentAttribute

  self.table_name = "tax_parameters"

  FEDERAL_COLUMNS = %i[
    standard_deduction_mfj_cents ss_wage_base_cents se_earnings_bps ss_rate_bps medicare_rate_bps additional_medicare_bps
    additional_medicare_threshold_mfj_cents qbi_bps qbi_threshold_mfj_cents home_office_simplified_rate_cents
    home_office_simplified_max_sqft safe_harbor_high_agi_threshold_cents annual_additions_limit_cents elective_deferral_limit_cents
  ].freeze

  money_attribute :standard_deduction_mfj, allow_blank: true
  money_attribute :ss_wage_base, allow_blank: true
  money_attribute :additional_medicare_threshold_mfj, allow_blank: true
  money_attribute :qbi_threshold_mfj, allow_blank: true
  money_attribute :home_office_simplified_rate, allow_blank: true
  money_attribute :safe_harbor_high_agi_threshold, allow_blank: true
  money_attribute :annual_additions_limit, allow_blank: true
  money_attribute :elective_deferral_limit, allow_blank: true
  percent_attribute :se_earnings_percent, bps: :se_earnings_bps, example: "92.35", allow_blank: true
  percent_attribute :ss_rate_percent, bps: :ss_rate_bps, example: "12.4", allow_blank: true
  percent_attribute :medicare_rate_percent, bps: :medicare_rate_bps, example: "2.9", allow_blank: true
  percent_attribute :additional_medicare_percent, bps: :additional_medicare_bps, example: "0.9", allow_blank: true
  percent_attribute :qbi_percent, bps: :qbi_bps, example: "20", allow_blank: true

  validates :year, presence: true, uniqueness: true, numericality: { only_integer: true, in: 2000..2100 }
  validates :standard_mileage_rate_tenth_cents, numericality: { only_integer: true, greater_than: 0, less_than: 2_147_483_647 }, unless: -> { @mileage_rate_error }
  validates :home_office_simplified_max_sqft, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate { errors.add(:mileage_rate_cents, @mileage_rate_error) if @mileage_rate_error }
  validate :brackets_valid

  def self.for_year(year) = find_by(year: year)

  def self.model_name = ActiveModel::Name.new(self, nil, "TaxParameter")

  def estimate_ready?
    FEDERAL_COLUMNS.all? { self[_1].present? } && brackets_mfj.present? && brackets_rise?(brackets_mfj)
  end

  def mileage_rate_cents
    @mileage_rate_input || (standard_mileage_rate_tenth_cents && Tenths.format(standard_mileage_rate_tenth_cents))
  end

  def mileage_rate_cents=(input)
    @mileage_rate_input = input
    @mileage_rate_error = nil
    self.standard_mileage_rate_tenth_cents = Tenths.parse(input)
  rescue Tenths::ParseError => e
    self.standard_mileage_rate_tenth_cents = nil
    @mileage_rate_error = e.message
  end

  def bracket_rows
    @bracket_rows_input || Array(brackets_mfj).map do |bracket|
      { "floor" => Money.new(bracket.fetch("floor_cents")).to_input, "rate" => PercentAttribute.format_bps(bracket.fetch("rate_bps")) }
    end
  end

  def bracket_rows=(rows)
    @bracket_rows_input = Array(rows).map { _1.to_h.stringify_keys.slice("floor", "rate") }
    @bracket_rows_error = nil
    filled = @bracket_rows_input.reject { |row| row.values.all?(&:blank?) }
    self.brackets_mfj = filled.empty? ? nil : filled.map { { "floor_cents" => Money.parse(_1["floor"]).cents, "rate_bps" => PercentAttribute.parse_bps(_1["rate"]) } }
  rescue Money::ParseError, PercentAttribute::ParseError
    @bracket_rows_error = "have an amount or rate that isn't a number"
  end

  private

  def brackets_valid
    return errors.add(:bracket_rows, @bracket_rows_error) if @bracket_rows_error
    return if brackets_mfj.blank?

    errors.add(:bracket_rows, "must start at $0 and rise") unless brackets_rise?(brackets_mfj)
  end

  def brackets_rise?(brackets)
    floors = brackets.map { _1["floor_cents"] }
    rates = brackets.map { _1["rate_bps"] }
    floors.first == 0 && floors.each_cons(2).all? { _1 < _2 } && rates.all? { (0..10_000).cover?(_1) }
  end
end
