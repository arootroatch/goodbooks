module ThemeHelper
  # --surface in tokens.css, so a phone's status bar blends into the top bar.
  THEME_COLORS = { "light" => "#ffffff", "dark" => "#0e1020" }.freeze

  def current_theme = Theme.normalize(cookies[Theme::COOKIE])

  def theme_attribute = (current_theme unless current_theme == "system")

  # theme_controller.js rewrites these media queries when the theme changes without a reload.
  def theme_color_meta_tags
    safe_join(THEME_COLORS.map do |scheme, color|
      media = if current_theme == "system" then "(prefers-color-scheme: #{scheme})"
      elsif current_theme == scheme then "all"
      else "not all"
      end
      tag.meta(name: "theme-color", content: color, media: media, data: { scheme: scheme })
    end, "\n")
  end
end
