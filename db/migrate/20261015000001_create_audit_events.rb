class CreateAuditEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_events do |t|
      t.references :user, null: false, foreign_key: true
      t.string :action, null: false
      t.string :auditable_type
      t.integer :auditable_id
      t.integer :business_id
      t.string :label, null: false, default: ""
      t.json :changed_values, null: false, default: {}
      t.string :summary
      t.datetime :created_at, null: false
    end
    add_index :audit_events, :created_at
    add_index :audit_events, %i[user_id created_at]
    add_index :audit_events, %i[auditable_type auditable_id]
    add_index :audit_events, %i[business_id created_at]
  end
end
