module ThemeHelper
  def current_theme = Theme.normalize(cookies[Theme::COOKIE])

  def theme_attribute = (current_theme unless current_theme == "system")
end
