module CategoriesHelper
  def category_groups(categories)
    { "Income" => categories.select(&:income?), "Expense" => categories.select(&:expense?),
      "Sales tax" => categories.select(&:sales_tax_remittance?) }.reject { |_, list| list.empty? }.to_a
  end

  def category_tithe_label(category)
    if category.income? then category.tithable? ? "Tithable" : "Not tithable"
    elsif category.tithe? then "Tithe payment"
    end
  end
end
