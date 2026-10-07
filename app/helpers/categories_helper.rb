module CategoriesHelper
  def category_tithe_label(category)
    if category.income? then category.tithable? ? "Tithable" : "Not tithable"
    elsif category.tithe? then "Tithe payment"
    end
  end
end
