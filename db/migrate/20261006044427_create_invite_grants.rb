class CreateInviteGrants < ActiveRecord::Migration[8.1]
  def change
    create_table :invite_grants do |t|
      t.references :invite, null: false, foreign_key: true
      t.references :business, null: false, foreign_key: true
      t.string :role, null: false
      t.timestamps
    end
  end
end
