module CategoriesHelper
  def category_groups(categories)
    { "Income" => categories.select(&:income?), "Expense" => categories.select(&:expense?),
      "Sales tax" => categories.select(&:sales_tax_remittance?) }.reject { |_, list| list.empty? }.to_a
  end

  def grouped_category_options(categories, selected = nil)
    grouped_options_for_select(category_groups(categories).map { |label, list| [ label, list.map { [ _1.name, _1.id ] } ] }, selected)
  end

  def category_tithe_label(category)
    if category.income? then category.tithable? ? "Tithable" : "Not tithable"
    elsif category.tithe? then "Tithe payment"
    end
  end
end
