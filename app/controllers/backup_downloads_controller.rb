class BackupDownloadsController < ApplicationController
  before_action :require_household_owner!

  def show
    snapshot = BackupSnapshots.new.find(params[:name]) or return head(:not_found)
    send_file snapshot.path, filename: snapshot.name, type: "application/vnd.sqlite3", disposition: :attachment
  end
end
