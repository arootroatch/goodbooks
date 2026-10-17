class AddLastSeenAtToSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :sessions, :last_seen_at, :datetime
    up_only { execute "UPDATE sessions SET last_seen_at = updated_at" }
  end
end
