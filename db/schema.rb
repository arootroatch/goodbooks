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

ActiveRecord::Schema[8.1].define(version: 2026_10_06_034451) do
  create_table "accounts", force: :cascade do |t|
    t.integer "business_id", null: false
    t.string "name", null: false
    t.string "source", null: false
    t.string "kind", null: false
    t.json "csv_mapping"
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_accounts_on_business_id"
  end

  create_table "businesses", force: :cascade do |t|
    t.integer "household_id", null: false
    t.integer "person_id", null: false
    t.string "name", null: false
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id"], name: "index_businesses_on_household_id"
    t.index ["person_id"], name: "index_businesses_on_person_id"
  end

  create_table "categories", force: :cascade do |t|
    t.integer "business_id", null: false
    t.string "name", null: false
    t.string "kind", null: false
    t.string "schedule_c_line", null: false
    t.integer "deductible_bps", default: 10000, null: false
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id", "name"], name: "index_categories_on_business_id_and_name", unique: true
    t.index ["business_id"], name: "index_categories_on_business_id"
  end

  create_table "households", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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

  create_table "people", force: :cascade do |t|
    t.integer "household_id", null: false
    t.integer "user_id"
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id"], name: "index_people_on_household_id"
    t.index ["user_id"], name: "index_people_on_user_id", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
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
  add_foreign_key "businesses", "households"
  add_foreign_key "businesses", "people"
  add_foreign_key "categories", "businesses"
  add_foreign_key "memberships", "businesses"
  add_foreign_key "memberships", "users"
  add_foreign_key "people", "households"
  add_foreign_key "people", "users"
  add_foreign_key "sessions", "users"
end
