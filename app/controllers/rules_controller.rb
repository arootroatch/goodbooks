class RulesController < ApplicationController
  include BusinessScoped

  PERMITTED = %i[field operator value amount_min amount_max outcome category_id].freeze

  before_action :require_editor!, except: :index
  before_action :set_rule, only: %i[edit update destroy move]

  def index
    @rules = @business.rules.ordered.includes(:category)
  end

  def new
    @rule = @business.rules.new(field: "payee", operator: "contains", outcome: "categorize",
                                value: params[:value], category_id: params[:category_id])
  end

  def create
    @rule = @business.rules.new(params.expect(rule: PERMITTED))
    if @rule.save
      redirect_to business_rules_path(@business), notice: "Rule created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @rule.update(params.expect(rule: PERMITTED))
      redirect_to business_rules_path(@business), notice: "Rule updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @rule.destroy!
    redirect_to business_rules_path(@business), notice: "Rule deleted.", status: :see_other
  end

  def move
    @rule.move_to!(params.expect(:position))
    head :no_content
  end

  def apply
    count = RuleApplier.new(@business).apply(@business.transactions.inbox.to_a)
    redirect_to business_inbox_path(@business), notice: "#{count} #{"transaction".pluralize(count)} categorized.", status: :see_other
  end

  private

  def set_rule
    @rule = @business.rules.find(params[:id])
  end
end
