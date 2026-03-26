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

ActiveRecord::Schema[8.1].define(version: 2026_03_26_221245) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "authentications", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "oauth_expires_at"
    t.string "oauth_refresh_token"
    t.string "oauth_token"
    t.string "provider"
    t.string "uid"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.datetime "verification_sent_at"
    t.string "verification_token"
    t.datetime "verified_at"
    t.index ["provider", "uid"], name: "index_authentications_on_provider_and_uid", unique: true
    t.index ["user_id", "provider"], name: "index_authentications_on_user_id_and_provider", unique: true
    t.index ["user_id"], name: "index_authentications_on_user_id"
    t.index ["verification_token"], name: "index_authentications_on_verification_token", unique: true
  end

  create_table "invitations", force: :cascade do |t|
    t.datetime "accepted_at"
    t.integer "accepted_by_id"
    t.datetime "created_at", null: false
    t.datetime "declined_at"
    t.string "email"
    t.datetime "expires_at", null: false
    t.integer "invitable_id", null: false
    t.string "invitable_type", null: false
    t.integer "invited_by_id", null: false
    t.string "project_role"
    t.datetime "revoked_at"
    t.integer "role_id", null: false
    t.string "status", default: "pending", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["accepted_by_id"], name: "index_invitations_on_accepted_by_id"
    t.index ["email", "invitable_type", "invitable_id"], name: "index_invitations_on_email_and_invitable_pending", unique: true, where: "status = 'pending'"
    t.index ["invitable_type", "invitable_id"], name: "index_invitations_on_invitable"
    t.index ["invitable_type", "invitable_id"], name: "index_invitations_on_invitable_type_and_invitable_id"
    t.index ["invited_by_id"], name: "index_invitations_on_invited_by_id"
    t.index ["role_id"], name: "index_invitations_on_role_id"
    t.index ["token"], name: "index_invitations_on_token", unique: true
  end

  create_table "memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "discarded_at"
    t.integer "role_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "workspace_id", null: false
    t.index ["discarded_at"], name: "index_memberships_on_discarded_at"
    t.index ["role_id"], name: "index_memberships_on_role_id"
    t.index ["user_id", "workspace_id"], name: "index_memberships_on_user_id_and_workspace_id", unique: true
    t.index ["user_id"], name: "index_memberships_on_user_id"
    t.index ["workspace_id"], name: "index_memberships_on_workspace_id"
  end

  create_table "project_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "pinned", default: false, null: false
    t.integer "project_id", null: false
    t.string "role", default: "editor", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["project_id", "user_id"], name: "index_project_memberships_on_project_id_and_user_id", unique: true
    t.index ["project_id"], name: "index_project_memberships_on_project_id"
    t.index ["user_id"], name: "index_project_memberships_on_user_id"
  end

  create_table "projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "created_by_id", null: false
    t.text "description"
    t.datetime "discarded_at"
    t.string "name", null: false
    t.string "primary_color"
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["created_by_id"], name: "index_projects_on_created_by_id"
    t.index ["discarded_at"], name: "index_projects_on_discarded_at"
    t.index ["workspace_id", "slug"], name: "index_projects_on_workspace_id_and_slug", unique: true
    t.index ["workspace_id"], name: "index_projects_on_workspace_id"
  end

  create_table "roles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.json "permissions", default: {}
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.integer "workspace_id"
    t.index ["workspace_id", "slug"], name: "index_roles_on_workspace_id_and_slug", unique: true
    t.index ["workspace_id"], name: "index_roles_on_workspace_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "user_preferences", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "docs_mode"
    t.string "locale"
    t.string "theme", default: "system"
    t.string "timezone"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_user_preferences_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.integer "failed_login_attempts", default: 0, null: false
    t.string "first_name"
    t.string "last_name"
    t.datetime "locked_at"
    t.string "password_digest", null: false
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "workspaces", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "discarded_at"
    t.integer "max_members", default: 5, null: false
    t.integer "max_projects", default: 3, null: false
    t.string "name", null: false
    t.string "plan", default: "free", null: false
    t.string "primary_color"
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["discarded_at"], name: "index_workspaces_on_discarded_at"
    t.index ["slug"], name: "index_workspaces_on_slug", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "authentications", "users"
  add_foreign_key "invitations", "roles"
  add_foreign_key "invitations", "users", column: "accepted_by_id"
  add_foreign_key "invitations", "users", column: "invited_by_id"
  add_foreign_key "memberships", "roles"
  add_foreign_key "memberships", "users"
  add_foreign_key "memberships", "workspaces"
  add_foreign_key "project_memberships", "projects"
  add_foreign_key "project_memberships", "users"
  add_foreign_key "projects", "users", column: "created_by_id"
  add_foreign_key "projects", "workspaces"
  add_foreign_key "roles", "workspaces"
  add_foreign_key "sessions", "users"
  add_foreign_key "user_preferences", "users"
end
