module MoneyAttribute
  extend ActiveSupport::Concern

  class_methods do
    def money_attribute(name, allow_blank: false)
      cents = "#{name}_cents"
      input_ivar = "@#{name}_input"
      error_ivar = "@#{name}_parse_error"

      define_method(name) do
        if instance_variable_defined?(input_ivar)
          instance_variable_get(input_ivar)
        elsif self[cents]
          Money.new(self[cents]).to_input
        end
      end

      define_method("#{name}=") do |input|
        instance_variable_set(input_ivar, input)
        instance_variable_set(error_ivar, nil)
        self[cents] = allow_blank && input.to_s.strip.empty? ? nil : Money.parse(input).cents
      rescue Money::ParseError => e
        self[cents] = nil
        instance_variable_set(error_ivar, e.message)
      end

      validate do
        message = instance_variable_defined?(error_ivar) && instance_variable_get(error_ivar)
        if message
          errors.add(name, message)
        elsif !allow_blank && self[cents].nil?
          errors.add(name, :blank)
        end
      end
    end
  end
end
