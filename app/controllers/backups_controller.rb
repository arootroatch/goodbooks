class BackupsController < ApplicationController
  before_action :require_household_owner!
  before_action :load_page

  def show
  end

  def create
    DatabaseBackupJob.perform_later
    redirect_to backups_path, notice: "Backup started. Refresh in a moment to see it.", status: :see_other
  end

  def update
    if @household.update(params.expect(household: [ :backup_retention ]))
      redirect_to backups_path, notice: "Retention saved.", status: :see_other
    else
      render :show, status: :unprocessable_content
    end
  end

  private

  def load_page
    snapshots = BackupSnapshots.new
    @snapshots = snapshots.all
    @latest = @snapshots.first
    @overdue = snapshots.overdue?
    @backup_error = ErrorEvent.unresolved.recent_first.find_by(source: DatabaseBackupJob.name)
    @household = Household.instance
  end
end
