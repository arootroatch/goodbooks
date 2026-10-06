class AddProfileAndTwoFactorToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :name, :string, null: false, default: ""
    add_column :users, :household_owner, :boolean, null: false, default: false
    add_column :users, :otp_secret, :string
    add_column :users, :otp_enabled_at, :datetime
    add_column :users, :otp_last_verified_at, :integer
    add_column :users, :recovery_code_digests, :json, null: false, default: []
  end
end
