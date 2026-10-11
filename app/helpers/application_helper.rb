module ApplicationHelper
  def primary_action(label, path) = link_to(label, path, class: "button primary")
  def secondary_action(label, path) = link_to(label, path, class: "button no-print")

  def confirm_button(label, path, confirm:, **options)
    button_to label, path, **options, form: { data: { turbo_confirm: confirm } }
  end

  def archive_button(target)
    record = target.last
    if record.archived?
      button_to "Unarchive", polymorphic_path(target, action: :unarchive), method: :patch
    else
      confirm_button "Archive", polymorphic_path(target, action: :archive), method: :patch,
                                confirm: "Archive this #{record.model_name.human.downcase}? It will be hidden until you unarchive it."
    end
  end

  def due_phrase(due_on, today = Date.current)
    days = (due_on - today).to_i
    if days.negative? then "#{pluralize(-days, 'day')} late"
    elsif days.zero? then "due today"
    else "due in #{pluralize(days, 'day')}"
    end
  end

  def money(cents)
    return "—" if cents.nil?
    return Money.new(cents).to_s unless cents.negative?

    tag.span("(#{Money.new(-cents)})", class: "neg")
  end

  def current_personal_book
    return @current_personal_book if defined?(@current_personal_book)

    @current_personal_book = Current.user.accessible_businesses.personal.first
  end

  def show_bank_connections?
    PlaidGateway.enabled? && (Current.user.household_owner? || Current.user.owned_books.exists?)
  end
end
