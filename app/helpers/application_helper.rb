module ApplicationHelper
  def primary_action(label, path) = link_to(label, path, class: "button primary")

  def money(cents)
    return "—" if cents.nil?
    return Money.new(cents).to_s unless cents.negative?

    tag.span("(#{Money.new(-cents)})", class: "neg")
  end

  def current_personal_book
    return @current_personal_book if defined?(@current_personal_book)

    @current_personal_book = Current.user.accessible_businesses.personal.first
  end
end
