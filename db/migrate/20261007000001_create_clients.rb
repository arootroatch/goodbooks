class CreateClients < ActiveRecord::Migration[8.1]
  def change
    create_table :clients do |t|
      t.references :business, null: false, foreign_key: true
      t.string :name, null: false
      t.string :email
      t.text :notes
      t.datetime :archived_at
      t.timestamps
    end
    add_index :clients, %i[business_id name], unique: true
  end
end
