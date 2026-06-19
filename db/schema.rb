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

ActiveRecord::Schema[8.1].define(version: 2026_06_19_165009) do
  create_table "action_text_rich_texts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

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

  create_table "activity_logs", force: :cascade do |t|
    t.string "action", null: false
    t.integer "actor_id"
    t.datetime "created_at", null: false
    t.json "metadata", default: {}
    t.integer "trackable_id", null: false
    t.string "trackable_type", null: false
    t.datetime "updated_at", null: false
    t.string "visibility", default: "workspace", null: false
    t.integer "workspace_id"
    t.index ["actor_id"], name: "index_activity_logs_on_actor_id"
    t.index ["trackable_type", "trackable_id"], name: "index_activity_logs_on_trackable"
    t.index ["workspace_id", "created_at"], name: "index_activity_logs_on_workspace_id_and_created_at"
    t.index ["workspace_id"], name: "index_activity_logs_on_workspace_id"
  end

  create_table "authentications", force: :cascade do |t|
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.string "email"
    t.datetime "oauth_expires_at"
    t.string "oauth_refresh_token"
    t.string "oauth_token"
    t.string "pending_invitation_token"
    t.string "pending_join_link_token"
    t.string "provider"
    t.string "uid"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.datetime "verified_at"
    t.index ["pending_invitation_token"], name: "index_authentications_on_pending_invitation_token", where: "pending_invitation_token IS NOT NULL"
    t.index ["provider", "uid"], name: "index_authentications_on_provider_and_uid", unique: true
    t.index ["user_id", "provider"], name: "index_authentications_on_user_id_and_provider", unique: true
    t.index ["user_id"], name: "index_authentications_on_user_id"
  end

  create_table "documents", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.index ["invited_by_id"], name: "index_invitations_on_invited_by_id"
    t.index ["role_id"], name: "index_invitations_on_role_id"
    t.index ["token"], name: "index_invitations_on_token", unique: true
  end

  create_table "magic_link_tokens", force: :cascade do |t|
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "expires_at", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_magic_link_tokens_on_email_unconsumed", unique: true, where: "consumed_at IS NULL"
    t.index ["token"], name: "index_magic_link_tokens_on_token", unique: true
  end

  create_table "memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "discarded_at"
    t.datetime "last_accessed_at"
    t.integer "role_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "workspace_id", null: false
    t.index ["discarded_at"], name: "index_memberships_on_discarded_at"
    t.index ["role_id"], name: "index_memberships_on_role_id"
    t.index ["user_id", "last_accessed_at"], name: "index_memberships_on_user_id_and_last_accessed_at"
    t.index ["user_id", "workspace_id"], name: "index_memberships_on_user_id_and_workspace_id", unique: true
    t.index ["user_id"], name: "index_memberships_on_user_id"
    t.index ["workspace_id"], name: "index_memberships_on_workspace_id"
  end

  create_table "noticed_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "idempotency_key"
    t.integer "notifications_count"
    t.json "params"
    t.bigint "record_id"
    t.string "record_type"
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_noticed_events_on_idempotency_key", unique: true, where: "idempotency_key IS NOT NULL"
    t.index ["record_type", "record_id"], name: "index_noticed_events_on_record"
  end

  create_table "noticed_notifications", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.datetime "read_at", precision: nil
    t.bigint "recipient_id", null: false
    t.string "recipient_type", null: false
    t.datetime "seen_at", precision: nil
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_noticed_notifications_on_event_id"
    t.index ["recipient_type", "recipient_id", "read_at", "created_at"], name: "index_noticed_notifications_on_recipient_read_created"
    t.index ["recipient_type", "recipient_id"], name: "index_noticed_notifications_on_recipient"
    t.index ["recipient_type", "recipient_id"], name: "index_noticed_notifications_unread", where: "read_at IS NULL"
    t.check_constraint "recipient_type = 'User'", name: "recipient_type_user_only_v1"
    t.check_constraint "seen_at IS NULL OR read_at IS NULL OR read_at >= seen_at", name: "seen_before_read"
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
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["created_by_id"], name: "index_projects_on_created_by_id"
    t.index ["discarded_at"], name: "index_projects_on_discarded_at"
    t.index ["workspace_id", "slug"], name: "index_projects_on_workspace_id_and_slug", unique: true
    t.index ["workspace_id"], name: "index_projects_on_workspace_id"
  end

  create_table "resources", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "created_by_id", null: false
    t.datetime "discarded_at"
    t.integer "position", default: 0, null: false
    t.integer "project_id", null: false
    t.integer "resourceable_id", null: false
    t.string "resourceable_type", null: false
    t.string "status", default: "draft", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_resources_on_created_by_id"
    t.index ["discarded_at"], name: "index_resources_on_discarded_at"
    t.index ["project_id", "position"], name: "index_resources_on_project_id_and_position"
    t.index ["project_id"], name: "index_resources_on_project_id"
    t.index ["resourceable_type", "resourceable_id"], name: "index_resources_on_resourceable_type_and_resourceable_id", unique: true
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
    t.datetime "digest_last_sent_at"
    t.datetime "digest_next_due_at"
    t.datetime "dismissed_notifications_redesign_banner_at"
    t.string "docs_mode"
    t.string "locale"
    t.json "notification_preferences", default: {"notification_types" => {"security" => true, "account_access" => true, "workspace_activity" => true, "project_activity" => true, "billing" => true}, "delivery_methods" => {"in_app" => {"enabled" => true}, "email" => {"enabled" => true, "frequency" => "instant"}}, "quiet_hours" => {"enabled" => false, "start" => "22:00", "end" => "07:00", "allow_urgent" => true, "active_days" => ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]}, "retention_days" => 90}, null: false
    t.string "theme", default: "system"
    t.string "timezone"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["digest_next_due_at"], name: "index_user_preferences_on_digest_next_due_at", where: "digest_next_due_at IS NOT NULL"
    t.index ["user_id"], name: "index_user_preferences_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "avatar_source", default: "initials", null: false
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.integer "failed_login_attempts", default: 0, null: false
    t.string "first_name"
    t.boolean "has_gravatar", default: false, null: false
    t.json "last_known_browsers", default: [], null: false
    t.string "last_name"
    t.datetime "locked_at"
    t.datetime "onboarded_at"
    t.string "password_digest"
    t.string "pending_email"
    t.datetime "pending_email_sent_at"
    t.string "pending_email_token"
    t.integer "personal_workspace_id"
    t.integer "primary_color", default: 210
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["pending_email_token"], name: "index_users_on_pending_email_token", unique: true
    t.index ["personal_workspace_id"], name: "index_users_on_personal_workspace_id"
    t.index ["personal_workspace_id"], name: "index_users_on_personal_workspace_id_unique", unique: true, where: "personal_workspace_id IS NOT NULL"
  end

  create_table "workspace_join_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "created_by_id", null: false
    t.datetime "revoked_at"
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["created_by_id"], name: "index_workspace_join_links_on_created_by_id"
    t.index ["token"], name: "index_workspace_join_links_on_token", unique: true
    t.index ["workspace_id", "revoked_at"], name: "index_workspace_join_links_on_workspace_id_and_revoked_at"
    t.index ["workspace_id"], name: "index_workspace_join_links_on_workspace_id"
    t.index ["workspace_id"], name: "index_workspace_join_links_unique_active_per_workspace", unique: true, where: "revoked_at IS NULL"
  end

  create_table "workspaces", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "discarded_at"
    t.string "join_policy", default: "invite", null: false
    t.string "logo_source", default: "initials", null: false
    t.integer "max_members", default: 5, null: false
    t.integer "max_projects", default: 3, null: false
    t.string "name", null: false
    t.boolean "personal", default: false, null: false
    t.string "plan", default: "free", null: false
    t.integer "primary_color", default: 210
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["discarded_at"], name: "index_workspaces_on_discarded_at"
    t.index ["join_policy"], name: "index_workspaces_on_join_policy"
    t.index ["slug"], name: "index_workspaces_on_slug", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "activity_logs", "users", column: "actor_id"
  add_foreign_key "activity_logs", "workspaces"
  add_foreign_key "authentications", "users"
  add_foreign_key "invitations", "roles"
  add_foreign_key "invitations", "users", column: "accepted_by_id"
  add_foreign_key "invitations", "users", column: "invited_by_id"
  add_foreign_key "memberships", "roles"
  add_foreign_key "memberships", "users"
  add_foreign_key "memberships", "workspaces"
  add_foreign_key "noticed_notifications", "noticed_events", column: "event_id", on_delete: :cascade
  add_foreign_key "project_memberships", "projects"
  add_foreign_key "project_memberships", "users"
  add_foreign_key "projects", "users", column: "created_by_id"
  add_foreign_key "projects", "workspaces"
  add_foreign_key "resources", "projects"
  add_foreign_key "resources", "users", column: "created_by_id"
  add_foreign_key "roles", "workspaces"
  add_foreign_key "sessions", "users"
  add_foreign_key "user_preferences", "users"
  add_foreign_key "users", "workspaces", column: "personal_workspace_id", on_delete: :nullify
  add_foreign_key "workspace_join_links", "users", column: "created_by_id"
  add_foreign_key "workspace_join_links", "workspaces"
end
