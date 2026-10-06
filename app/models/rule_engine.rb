module RuleEngine
  module_function

  def match(attrs, rules)
    rules.find { |rule| matches?(rule, attrs) }
  end

  def matches?(rule, attrs)
    text_matches?(rule, normalize(attrs[rule.field.to_sym])) && amount_matches?(rule, attrs[:amount_cents].to_i.abs)
  end

  def text_matches?(rule, text)
    value = normalize(rule.value)
    case rule.operator
    when "contains" then text.include?(value)
    when "equals" then text == value
    when "starts_with" then text.start_with?(value)
    else false
    end
  end

  def amount_matches?(rule, cents)
    (rule.amount_min_cents.nil? || cents >= rule.amount_min_cents) &&
      (rule.amount_max_cents.nil? || cents <= rule.amount_max_cents)
  end

  def normalize(text) = text.to_s.downcase.squish
end
