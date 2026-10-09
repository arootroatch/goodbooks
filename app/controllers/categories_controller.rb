class CategoriesController < ApplicationController
  include BusinessScoped

  PERMITTED = %i[name kind schedule_c_line deductible_percent tithable tithe sales_tax_treatment].freeze

  before_action :require_editor!, except: :index
  before_action :set_category, only: %i[edit update]

  def index
    @categories = @business.categories.order(:archived_at, :kind, :name)
  end

  def new
    @category = @business.categories.new(kind: "expense", schedule_c_line: (@business.personal? ? nil : "18"))
  end

  def create
    @category = @business.categories.new(params.expect(category: PERMITTED))
    if @category.save
      redirect_to business_categories_path(@business), notice: "Category created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    attrs = params.expect(category: [ *PERMITTED, :archived ])
    archived = attrs.delete(:archived)
    @category.assign_attributes(attrs)
    @category.archived_at = archived == "1" ? (@category.archived_at || Time.current) : nil unless archived.nil?
    if @category.save
      redirect_to business_categories_path(@business), notice: "Category updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_category
    @category = @business.categories.find(params[:id])
  end
end
