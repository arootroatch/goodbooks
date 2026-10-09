class CategoriesController < ApplicationController
  include BusinessScoped
  include Archiving

  PERMITTED = %i[name kind schedule_c_line deductible_percent tithable tithe sales_tax_treatment].freeze

  before_action :require_editor!, except: :index
  before_action :set_category, only: %i[edit update archive unarchive]

  def index
    @categories = @business.categories.order(:archived_at, :kind, :name)
  end

  def new
    @category = @business.categories.new(kind: "expense", schedule_c_line: (@business.personal? ? nil : "18"))
  end

  def create
    @category = @business.categories.new(params.expect(category: PERMITTED))
    if @category.save
      redirect_to category_return_path(@category), notice: "Category created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @category.update(params.expect(category: PERMITTED))
      redirect_to business_categories_path(@business), notice: "Category updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def archivable = @category

  # Back to the transaction that asked for this category, with it selected; otherwise the category list.
  def category_return_path(category)
    transaction = Transaction.for_businesses(@business.id).find_by(id: params[:transaction_id]) if params[:transaction_id].is_a?(String)
    transaction ? edit_business_transaction_path(@business, transaction, category_id: category.id) : business_categories_path(@business)
  end

  def set_category
    @category = @business.categories.find(params[:id])
  end
end
