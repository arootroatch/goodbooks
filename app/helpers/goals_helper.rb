module GoalsHelper
  # Sits beside the goal's name, not in its bar, so every bar in a list is the same length.
  def goal_met_badge(row)
    tag.span("Met", class: "badge badge-pos goal-tag") if row.met?
  end
end
