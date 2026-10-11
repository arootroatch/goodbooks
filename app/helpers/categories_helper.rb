module CategoriesHelper
  def grouped_category_options(categories, selected = nil)
    grouped_options_for_select({ "Income" => categories.select(&:income?).map { [ _1.name, _1.id ] },
                                 "Expense" => categories.select(&:expense?).map { [ _1.name, _1.id ] } }, selected)
  end

  def category_tithe_label(category)
    if category.income? then category.tithable? ? "Tithable" : "Not tithable"
    elsif category.tithe? then "Tithe payment"
    end
  end
end
