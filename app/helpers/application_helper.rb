module ApplicationHelper
  def primary_action(label, path) = link_to(label, path, class: "button primary")

  def money(cents)
    return "—" if cents.nil?
    return Money.new(cents).to_s unless cents.negative?

    tag.span("(#{Money.new(-cents)})", class: "neg")
  end
end
