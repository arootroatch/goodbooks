module Theme
  CHOICES = %w[system light dark].freeze
  COOKIE = :theme

  def self.normalize(value) = CHOICES.include?(value) ? value : "system"
end
