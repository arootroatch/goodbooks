class CreateErrorEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :error_events do |t|
      t.string :fingerprint, null: false, index: { unique: true }
      t.string :error_class, null: false
      t.text :message, null: false
      t.text :backtrace, null: false
      t.string :source
      t.integer :occurrences, null: false, default: 1
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.integer :last_user_id
      t.datetime :resolved_at
      t.timestamps
    end
  end
end
