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

ActiveRecord::Schema[8.0].define(version: 2025_06_07_181041) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "courses", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "level"
    t.index "lower((name)::text) varchar_pattern_ops", name: "index_courses_on_LOWER_name_varchar_pattern_ops"
    t.index ["name", "level"], name: "index_courses_on_name_and_level"
    t.index ["user_id", "level"], name: "index_courses_on_user_id_and_level"
    t.index ["user_id"], name: "index_courses_on_user_id"
  end

  create_table "grades", force: :cascade do |t|
    t.string "letter_grade"
    t.decimal "numeric_grade"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "course_id", null: false
    t.index ["course_id", "letter_grade"], name: "index_grades_on_course_id_and_letter_grade"
    t.index ["course_id", "numeric_grade"], name: "index_grades_on_course_id_and_numeric_grade"
    t.index ["course_id"], name: "index_grades_on_course_id"
    t.index ["letter_grade"], name: "index_grades_on_letter_grade"
    t.index ["numeric_grade"], name: "index_grades_incomplete", where: "(numeric_grade = 0.0)"
    t.index ["user_id", "letter_grade"], name: "index_grades_on_user_id_and_letter_grade"
    t.index ["user_id", "numeric_grade"], name: "index_grades_on_user_id_and_numeric_grade"
    t.index ["user_id"], name: "index_grades_on_user_id"
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "class_name"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.string "command", limit: 2048
    t.text "arguments"
    t.text "description"
    t.boolean "static", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "next_at"
    t.string "method_name"
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["next_at"], name: "index_solid_queue_recurring_tasks_on_next_at"
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.string "username"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "role"
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.integer "grades_count", default: 0
    t.string "seed_password"
    t.integer "failed_attempts", default: 0, null: false
    t.string "unlock_token"
    t.datetime "locked_at"
    t.integer "courses_count", default: 0, null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["role"], name: "index_users_on_role"
    t.index ["seed_password"], name: "index_users_on_seed_password"
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
    t.check_constraint "role::text = ANY (ARRAY['Student'::character varying::text, 'Teacher'::character varying::text, 'Admin'::character varying::text])", name: "users_role_check"
  end

  add_foreign_key "courses", "users"
  add_foreign_key "grades", "courses"
  add_foreign_key "grades", "users"
end
