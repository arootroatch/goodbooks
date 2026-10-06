module Tenths
  class ParseError < ArgumentError; end

  module_function

  def parse(input)
    text = input.to_s.strip.delete(",")
    raise ParseError, "can't be blank" if text.empty?

    match = text.match(/\A(\d*)(?:\.(\d))?\z/)
    if match.nil? || (match[1].empty? && match[2].nil?)
      raise ParseError, "must be a number with at most one decimal place"
    end

    match[1].to_i * 10 + match[2].to_i
  end

  def format(tenths) = "#{tenths / 10}.#{tenths % 10}"
end
