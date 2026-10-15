# "Safari on iOS" from a User-Agent header. Order matters: Edge and Chrome on iOS also claim Chrome/Safari, iOS claims Mac OS X.
class UserAgentLabel
  BROWSERS = [ [ /Edg\//, "Edge" ], [ /OPR\//, "Opera" ], [ /Firefox\/|FxiOS\//, "Firefox" ], [ /Chrome\/|CriOS\//, "Chrome" ], [ /Safari\//, "Safari" ] ].freeze
  SYSTEMS = [ [ /iPhone|iPad|iPod/, "iOS" ], [ /Android/, "Android" ], [ /Mac OS X|Macintosh/, "macOS" ], [ /Windows/, "Windows" ], [ /CrOS/, "ChromeOS" ], [ /Linux/, "Linux" ] ].freeze

  def self.call(user_agent)
    return "Unknown device" if user_agent.blank?

    "#{match(BROWSERS, user_agent) || "Unknown browser"} on #{match(SYSTEMS, user_agent) || "unknown OS"}"
  end

  def self.match(table, user_agent) = table.find { |pattern, _| pattern.match?(user_agent) }&.last

  private_class_method :match
end
