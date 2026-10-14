class GoalsController < ApplicationController
  include BusinessScoped
  include Archiving

  FIELDS = %i[name target target_date account_id match_field match_operator match_value match_amount_min match_amount_max].freeze

  before_action :require_editor!, except: :index
  before_action :set_goal, only: %i[edit update destroy move archive unarchive]

  def index
    @rows = Goals::Progress.for_book(@business)
    @completed = @business.goals.where.not(archived_at: nil).order(archived_at: :desc)
  end

  def new
    @goal = @business.goals.new(kind: params[:kind] == "savings" ? "savings" : "payments", match_field: "payee", match_operator: "contains")
  end

  def create
    @goal = @business.goals.new(params.expect(goal: [ :kind, *FIELDS ]))
    if @goal.save
      redirect_to business_goals_path(@business), notice: saved_notice
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @goal.update(params.expect(goal: FIELDS))
      redirect_to business_goals_path(@business), notice: saved_notice
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @goal.destroy!
    redirect_to business_goals_path(@business), notice: "Goal deleted.", status: :see_other
  end

  def move
    @goal.move_to!(params.expect(:position))
    head :no_content
  end

  private

  def archivable = @goal

  def set_goal
    @goal = @business.goals.find(params[:id])
  end

  def saved_notice
    count = @goal.rematched_count
    count ? "Goal saved. #{count} existing #{"transaction".pluralize(count)} linked." : "Goal saved."
  end
end
