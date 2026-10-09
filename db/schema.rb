# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_09_050003) do
  create_table "accounts", force: :cascade do |t|
    t.integer "business_id", null: false
    t.string "name", null: false
    t.string "source", null: false
    t.string "kind", null: false
    t.json "csv_mapping"
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "plaid_item_id"
    t.string "plaid_account_id"
    t.string "plaid_mask"
    t.string "plaid_name"
    t.date "plaid_sync_from"
    t.index ["business_id"], name: "index_accounts_on_business_id"
    t.index ["plaid_account_id"], name: "index_accounts_on_plaid_account_id", unique: true, where: "plaid_account_id IS NOT NULL"
    t.index ["plaid_item_id"], name: "index_accounts_on_plaid_item_id"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "businesses", force: :cascade do |t|
    t.integer "household_id", null: false
    t.integer "person_id"
    t.string "name", null: false
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "kind", default: "business", null: false
    t.date "tithe_start_on"
    t.index ["household_id"], name: "index_businesses_on_household_id"
    t.index ["household_id"], name: "index_businesses_one_personal_per_household", unique: true, where: "kind = 'personal'"
    t.index ["person_id"], name: "index_businesses_on_person_id"
  end

  create_table "categories", force: :cascade do |t|
    t.integer "business_id", null: false
    t.string "name", null: false
    t.string "kind", null: false
    t.string "schedule_c_line"
    t.integer "deductible_bps", default: 10000, null: false
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "tithable", default: true, null: false
    t.boolean "tithe", default: false, null: false
    t.index ["business_id", "name"], name: "index_categories_on_business_id_and_name", unique: true
    t.index ["business_id"], name: "index_categories_on_business_id"
  end

  create_table "clients", force: :cascade do |t|
    t.integer "business_id", null: false
    t.string "name", null: false
    t.string "email"
    t.text "notes"
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id", "name"], name: "index_clients_on_business_id_and_name", unique: true
    t.index ["business_id"], name: "index_clients_on_business_id"
  end

  create_table "csv_imports", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "status", default: "previewed", null: false
    t.integer "row_count", default: 0, null: false
    t.integer "new_count", default: 0, null: false
    t.integer "duplicate_count", default: 0, null: false
    t.integer "error_count", default: 0, null: false
    t.datetime "committed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "mapping"
    t.index ["account_id"], name: "index_csv_imports_on_account_id"
  end

  create_table "households", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "singleton", default: true, null: false
    t.index ["singleton"], name: "index_households_on_singleton", unique: true
  end

  create_table "invite_grants", force: :cascade do |t|
    t.integer "invite_id", null: false
    t.integer "business_id", null: false
    t.string "role", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_invite_grants_on_business_id"
    t.index ["invite_id"], name: "index_invite_grants_on_invite_id"
  end

  create_table "invites", force: :cascade do |t|
    t.integer "created_by_id", null: false
    t.string "email"
    t.string "token_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "accepted_at"
    t.integer "accepted_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["accepted_by_id"], name: "index_invites_on_accepted_by_id"
    t.index ["created_by_id"], name: "index_invites_on_created_by_id"
    t.index ["token_digest"], name: "index_invites_on_token_digest", unique: true
  end

  create_table "invoice_payments", force: :cascade do |t|
    t.integer "invoice_id", null: false
    t.integer "deposit_id", null: false
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deposit_id"], name: "index_invoice_payments_on_deposit_id"
    t.index ["invoice_id", "deposit_id"], name: "index_invoice_payments_on_invoice_id_and_deposit_id", unique: true
    t.index ["invoice_id"], name: "index_invoice_payments_on_invoice_id"
  end

  create_table "invoices", force: :cascade do |t|
    t.integer "business_id", null: false
    t.integer "client_id", null: false
    t.string "number", null: false
    t.date "issue_date", null: false
    t.date "due_date", null: false
    t.integer "amount_cents", null: false
    t.text "description"
    t.string "status", default: "sent", null: false
    t.date "paid_on"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id", "number"], name: "index_invoices_on_business_id_and_number", unique: true
    t.index ["business_id", "status"], name: "index_invoices_on_business_id_and_status"
    t.index ["business_id"], name: "index_invoices_on_business_id"
    t.index ["client_id"], name: "index_invoices_on_client_id"
  end

  create_table "memberships", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "business_id", null: false
    t.string "role", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_memberships_on_business_id"
    t.index ["user_id", "business_id"], name: "index_memberships_on_user_id_and_business_id", unique: true
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "mileage_entries", force: :cascade do |t|
    t.integer "business_id", null: false
    t.date "driven_on", null: false
    t.string "purpose", null: false
    t.string "from_location"
    t.string "to_location"
    t.integer "miles_tenths", null: false
    t.boolean "round_trip", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_mileage_entries_on_business_id"
    t.index ["driven_on"], name: "index_mileage_entries_on_driven_on"
  end

  create_table "people", force: :cascade do |t|
    t.integer "household_id", null: false
    t.integer "user_id"
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id"], name: "index_people_on_household_id"
    t.index ["user_id"], name: "index_people_on_user_id", unique: true
  end

  create_table "plaid_items", force: :cascade do |t|
    t.integer "household_id", null: false
    t.integer "created_by_id", null: false
    t.string "institution_name", null: false
    t.string "item_id", null: false
    t.text "access_token", null: false
    t.text "cursor"
    t.string "status", default: "ok", null: false
    t.datetime "last_synced_at"
    t.string "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_plaid_items_on_created_by_id"
    t.index ["household_id"], name: "index_plaid_items_on_household_id"
    t.index ["item_id"], name: "index_plaid_items_on_item_id", unique: true
  end

  create_table "rules", force: :cascade do |t|
    t.integer "business_id", null: false
    t.integer "position", null: false
    t.string "field", null: false
    t.string "operator", null: false
    t.string "value", null: false
    t.integer "amount_min_cents"
    t.integer "amount_max_cents"
    t.string "outcome", null: false
    t.integer "category_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_rules_on_business_id"
    t.index ["category_id"], name: "index_rules_on_category_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "tax_parameters", force: :cascade do |t|
    t.integer "year", null: false
    t.integer "standard_mileage_rate_tenth_cents", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["year"], name: "index_tax_parameters_on_year", unique: true
  end

  create_table "transactions", force: :cascade do |t|
    t.integer "account_id", null: false
    t.date "posted_on", null: false
    t.integer "amount_cents", null: false
    t.string "payee", null: false
    t.string "memo"
    t.integer "category_id"
    t.boolean "transfer", default: false, null: false
    t.boolean "excluded", default: false, null: false
    t.string "external_id"
    t.string "categorized_by"
    t.integer "rule_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "plaid_transaction_id"
    t.string "review_reason"
    t.index ["account_id", "external_id"], name: "index_transactions_on_account_id_and_external_id", unique: true, where: "external_id IS NOT NULL"
    t.index ["account_id", "plaid_transaction_id"], name: "index_transactions_on_account_id_and_plaid_transaction_id", unique: true, where: "plaid_transaction_id IS NOT NULL"
    t.index ["account_id"], name: "index_transactions_on_account_id"
    t.index ["category_id"], name: "index_transactions_on_category_id"
    t.index ["posted_on"], name: "index_transactions_on_posted_on"
    t.index ["review_reason"], name: "index_transactions_on_review_reason", where: "review_reason IS NOT NULL"
    t.index ["rule_id"], name: "index_transactions_on_rule_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name", default: "", null: false
    t.boolean "household_owner", default: false, null: false
    t.string "otp_secret"
    t.datetime "otp_enabled_at"
    t.integer "otp_last_verified_at"
    t.json "recovery_code_digests", default: [], null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "accounts", "businesses"
  add_foreign_key "accounts", "plaid_items"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "businesses", "households"
  add_foreign_key "businesses", "people"
  add_foreign_key "categories", "businesses"
  add_foreign_key "clients", "businesses"
  add_foreign_key "csv_imports", "accounts"
  add_foreign_key "invite_grants", "businesses"
  add_foreign_key "invite_grants", "invites"
  add_foreign_key "invites", "users", column: "accepted_by_id"
  add_foreign_key "invites", "users", column: "created_by_id"
  add_foreign_key "invoice_payments", "invoices"
  add_foreign_key "invoice_payments", "transactions", column: "deposit_id"
  add_foreign_key "invoices", "businesses"
  add_foreign_key "invoices", "clients"
  add_foreign_key "memberships", "businesses"
  add_foreign_key "memberships", "users"
  add_foreign_key "mileage_entries", "businesses"
  add_foreign_key "people", "households"
  add_foreign_key "people", "users"
  add_foreign_key "plaid_items", "households"
  add_foreign_key "plaid_items", "users", column: "created_by_id"
  add_foreign_key "rules", "businesses"
  add_foreign_key "rules", "categories"
  add_foreign_key "sessions", "users"
  add_foreign_key "transactions", "accounts"
  add_foreign_key "transactions", "categories"
  add_foreign_key "transactions", "rules", on_delete: :nullify
end
