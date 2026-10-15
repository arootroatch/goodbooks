# Exposes an integer basis-point column as percentage text: "9.25", "9.25%" ↔ 925.
module PercentAttribute
  extend ActiveSupport::Concern

  class ParseError < ArgumentError; end

  FORMAT = /\A\d{1,3}(\.\d{1,2})?\z/

  def self.parse_bps(input)
    text = input.to_s.strip.delete_suffix("%").strip
    raise ParseError, "is not a percentage" unless text.match?(FORMAT)

    (Rational(text) * 100).to_i
  end

  def self.format_bps(bps)
    value = Rational(bps, 100)
    value.denominator == 1 ? value.to_i.to_s : format("%.2f", value).sub(/0\z/, "")
  end

  class_methods do
    def percent_attribute(name, bps:, example:, allow_blank: false)
      input_ivar = "@#{name}_input"
      invalid_ivar = "@#{name}_invalid"

      define_method(name) do
        if instance_variable_defined?(input_ivar)
          instance_variable_get(input_ivar)
        elsif self[bps]
          PercentAttribute.format_bps(self[bps])
        end
      end

      define_method("#{name}=") do |input|
        instance_variable_set(input_ivar, input)
        instance_variable_set(invalid_ivar, false)
        self[bps] = allow_blank && input.to_s.strip.empty? ? nil : PercentAttribute.parse_bps(input)
      rescue ParseError
        self[bps] = nil
        instance_variable_set(invalid_ivar, true)
      end

      validate do
        errors.add(name, "is not a percentage like #{example}") if instance_variable_get(invalid_ivar)
      end
    end
  end
end
