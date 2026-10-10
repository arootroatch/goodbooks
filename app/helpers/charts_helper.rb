module ChartsHelper
  WIDTH = 600
  HEIGHT = 220
  LEFT = 48
  RIGHT = 592
  TOP = 12
  BOTTOM = 192
  GRID_STEPS = 4

  def bar_chart(labels:, series:, label:, faded_index: nil)
    max = chart_max(series.flat_map { _1[:values] })
    parts = chart_gridlines(max)
    group_width = labels.empty? ? 0 : (RIGHT - LEFT).to_f / labels.size
    bar_width = group_width * 0.7 / [ series.size, 1 ].max

    labels.each_with_index do |name, i|
      group_x = LEFT + group_width * i
      faded = i == faded_index
      series.each_with_index do |s, j|
        value = s[:values][i].to_i
        next unless value.positive?

        height = (BOTTOM - TOP) * value.to_f / max
        parts << tag.rect(x: (group_x + group_width * 0.15 + bar_width * j).round(1), y: (BOTTOM - height).round(1),
                          width: bar_width.round(1), height: height.round(1), rx: 1.5,
                          class: [ "bar", "bar-#{s[:key]}", ("faded" if faded) ]) do
          tag.title("#{name} #{s[:name].downcase}: #{Money.new(value)}")
        end
      end
      parts << tag.text(name, x: (group_x + group_width / 2).round(1), y: HEIGHT - 10, class: "chart-axis", "text-anchor": "middle")
    end

    tag.svg(safe_join(parts), class: "chart", role: "img", aria: { label: }, viewBox: "0 0 #{WIDTH} #{HEIGHT}")
  end

  def compact_dollars(cents)
    dollars = cents / 100.0
    dollars >= 1000 ? "$#{trim_number(dollars / 1000)}k" : "$#{trim_number(dollars)}"
  end

  def hbar_list(rows)
    max = rows.map { _1[:cents] }.max.to_i
    items = rows.map do |row|
      percent = max.positive? ? (100.0 * row[:cents] / max).round(1) : 0
      tag.li do
        safe_join([ tag.span(row[:label], class: "hbar-label"),
                    tag.span(tag.span(class: "hbar-fill", style: "width: #{percent}%"), class: "hbar-track"),
                    tag.span(Money.new(row[:cents]).to_s, class: "hbar-value num") ])
      end
    end
    tag.ul(safe_join(items), class: "hbar-list")
  end

  private

  def chart_gridlines(max)
    (0..GRID_STEPS).flat_map do |step|
      y = (BOTTOM - (BOTTOM - TOP) * step.to_f / GRID_STEPS).round(1)
      [ tag.line(x1: LEFT, x2: RIGHT, y1: y, y2: y, class: "chart-grid"),
        tag.text(compact_dollars(max * step / GRID_STEPS), x: LEFT - 6, y: y + 3, class: "chart-axis", "text-anchor": "end") ]
    end
  end

  # Rounds up to 1, 2, 5 or 10 times a power of ten so gridlines land on round numbers.
  def chart_max(values)
    max = values.max.to_i
    return 100_000 unless max.positive?

    magnitude = 10**Math.log10(max).floor
    [ 1, 2, 5, 10 ].map { _1 * magnitude }.find { _1 >= max }
  end

  def trim_number(number)
    rounded = number.round(1)
    rounded == rounded.to_i ? rounded.to_i.to_s : rounded.to_s
  end
end
