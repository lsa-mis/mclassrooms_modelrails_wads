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

ActiveRecord::Schema[8.1].define(version: 2026_07_07_030007) do
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

  create_table "availability_blocks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "ends_at", null: false
    t.integer "room_id", null: false
    t.datetime "starts_at", null: false
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["room_id", "starts_at"], name: "index_availability_blocks_on_room_id_and_starts_at"
    t.index ["room_id"], name: "index_availability_blocks_on_room_id"
    t.index ["workspace_id"], name: "index_availability_blocks_on_workspace_id"
  end

  create_table "buildings", force: :cascade do |t|
    t.string "abbreviation"
    t.string "address"
    t.string "bldrecnbr", null: false
    t.integer "campus_id"
    t.string "city"
    t.string "country"
    t.datetime "created_at", null: false
    t.datetime "hidden_at"
    t.integer "hidden_by_id"
    t.boolean "in_feed", default: false, null: false
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.string "name", null: false
    t.string "nickname"
    t.string "state"
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.string "zip"
    t.index ["bldrecnbr"], name: "index_buildings_on_bldrecnbr", unique: true
    t.index ["campus_id"], name: "index_buildings_on_campus_id"
    t.index ["hidden_at"], name: "index_buildings_on_hidden_at"
    t.index ["hidden_by_id"], name: "index_buildings_on_hidden_by_id"
    t.index ["in_feed"], name: "index_buildings_on_in_feed"
    t.index ["workspace_id"], name: "index_buildings_on_workspace_id"
  end

  create_table "campuses", force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["workspace_id", "code"], name: "index_campuses_on_workspace_and_code", unique: true
    t.index ["workspace_id"], name: "index_campuses_on_workspace_id"
  end

  create_table "characteristic_display_rules", force: :cascade do |t|
    t.string "category_override"
    t.datetime "created_at", null: false
    t.boolean "filterable", default: true, null: false
    t.string "icon_key"
    t.string "short_code", null: false
    t.boolean "team_learning", default: false, null: false
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["workspace_id", "short_code"], name: "index_characteristic_display_rules_on_workspace_and_code", unique: true
    t.index ["workspace_id"], name: "index_characteristic_display_rules_on_workspace_id"
  end

  create_table "editor_assignments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "unit_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "workspace_id", null: false
    t.index ["unit_id"], name: "index_editor_assignments_on_unit_id"
    t.index ["user_id", "unit_id"], name: "index_editor_assignments_on_user_id_and_unit_id", unique: true
    t.index ["user_id"], name: "index_editor_assignments_on_user_id"
    t.index ["workspace_id"], name: "index_editor_assignments_on_workspace_id"
  end

  create_table "floors", force: :cascade do |t|
    t.integer "building_id", null: false
    t.datetime "created_at", null: false
    t.string "label", null: false
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["building_id", "label"], name: "index_floors_on_building_id_and_label", unique: true
    t.index ["building_id"], name: "index_floors_on_building_id"
    t.index ["workspace_id"], name: "index_floors_on_workspace_id"
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
    t.datetime "revoked_at"
    t.integer "role_id"
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
    t.string "intent"
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

  create_table "roles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.json "permissions", default: {}
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.integer "workspace_id"
    t.index ["slug"], name: "index_roles_on_slug_where_global", unique: true, where: "workspace_id IS NULL"
    t.index ["workspace_id", "slug"], name: "index_roles_on_workspace_id_and_slug", unique: true
    t.index ["workspace_id"], name: "index_roles_on_workspace_id"
  end

  create_table "room_characteristics", force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.string "long_description"
    t.integer "room_id", null: false
    t.string "short_code", null: false
    t.string "status"
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["room_id", "code"], name: "index_room_characteristics_on_room_id_and_code", unique: true
    t.index ["room_id"], name: "index_room_characteristics_on_room_id"
    t.index ["short_code"], name: "index_room_characteristics_on_short_code"
    t.index ["workspace_id"], name: "index_room_characteristics_on_workspace_id"
  end

  create_table "room_contacts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "room_id", null: false
    t.string "scheduling_detail_url"
    t.string "scheduling_email"
    t.string "scheduling_name"
    t.string "scheduling_phone"
    t.string "scheduling_usage_guidelines_url"
    t.string "support_department_description"
    t.string "support_department_id"
    t.string "support_email"
    t.string "support_phone"
    t.string "support_url"
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["room_id"], name: "index_room_contacts_on_room_id", unique: true
    t.index ["workspace_id"], name: "index_room_contacts_on_workspace_id"
  end

  create_table "room_gallery_images", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "position", default: 0, null: false
    t.integer "room_id", null: false
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["room_id", "position"], name: "index_room_gallery_images_on_room_id_and_position"
    t.index ["room_id"], name: "index_room_gallery_images_on_room_id"
    t.index ["workspace_id"], name: "index_room_gallery_images_on_workspace_id"
  end

  create_table "rooms", force: :cascade do |t|
    t.integer "ada_seat_count"
    t.integer "building_id", null: false
    t.string "building_name"
    t.integer "campus_id"
    t.datetime "created_at", null: false
    t.string "department_description"
    t.string "department_group"
    t.string "department_group_description"
    t.string "department_id"
    t.string "facility_code"
    t.string "facility_code_normalized"
    t.integer "floor_id"
    t.datetime "hidden_at"
    t.integer "hidden_by_id"
    t.boolean "in_feed", default: false, null: false
    t.integer "instructional_seat_count"
    t.string "nickname"
    t.string "rmrecnbr", null: false
    t.string "room_number"
    t.string "room_type"
    t.integer "square_feet"
    t.integer "unit_id"
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["building_id"], name: "index_rooms_on_building_id"
    t.index ["campus_id"], name: "index_rooms_on_campus_id"
    t.index ["facility_code_normalized"], name: "index_rooms_on_facility_code_normalized"
    t.index ["floor_id"], name: "index_rooms_on_floor_id"
    t.index ["hidden_at"], name: "index_rooms_on_hidden_at"
    t.index ["hidden_by_id"], name: "index_rooms_on_hidden_by_id"
    t.index ["in_feed"], name: "index_rooms_on_in_feed"
    t.index ["rmrecnbr"], name: "index_rooms_on_rmrecnbr", unique: true
    t.index ["room_type", "instructional_seat_count"], name: "index_rooms_on_room_type_and_instructional_seat_count"
    t.index ["unit_id"], name: "index_rooms_on_unit_id"
    t.index ["workspace_id"], name: "index_rooms_on_workspace_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "sync_phases", force: :cascade do |t|
    t.json "counters", default: {}, null: false
    t.datetime "created_at", null: false
    t.json "error_messages", default: [], null: false
    t.datetime "finished_at"
    t.string "key", null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.integer "sync_run_id", null: false
    t.datetime "updated_at", null: false
    t.json "warnings", default: [], null: false
    t.integer "workspace_id", null: false
    t.index ["sync_run_id", "key"], name: "index_sync_phases_on_sync_run_id_and_key", unique: true
    t.index ["sync_run_id"], name: "index_sync_phases_on_sync_run_id"
    t.index ["workspace_id"], name: "index_sync_phases_on_workspace_id"
  end

  create_table "sync_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "dry_run", default: false, null: false
    t.datetime "finished_at"
    t.datetime "started_at"
    t.string "status", default: "running", null: false
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["workspace_id"], name: "index_sync_runs_on_workspace_id"
  end

  create_table "sync_scope_rules", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "rule_type", null: false
    t.datetime "updated_at", null: false
    t.string "value", null: false
    t.integer "workspace_id", null: false
    t.index ["workspace_id", "rule_type", "value"], name: "index_sync_scope_rules_on_workspace_type_and_value", unique: true
    t.index ["workspace_id"], name: "index_sync_scope_rules_on_workspace_id"
  end

  create_table "unit_display_names", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "department_group", null: false
    t.string "display_name", null: false
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["workspace_id", "department_group"], name: "index_unit_display_names_on_workspace_and_dept_group", unique: true
    t.index ["workspace_id"], name: "index_unit_display_names_on_workspace_id"
  end

  create_table "units", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "department_group", null: false
    t.string "description"
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["workspace_id", "department_group"], name: "index_units_on_workspace_and_dept_group", unique: true
    t.index ["workspace_id"], name: "index_units_on_workspace_id"
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
    t.datetime "passkey_prompt_seen_at"
    t.string "password_digest"
    t.string "pending_email"
    t.datetime "pending_email_sent_at"
    t.string "pending_email_token"
    t.integer "personal_workspace_id"
    t.integer "primary_color", default: 210
    t.datetime "updated_at", null: false
    t.string "webauthn_handle"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["pending_email_token"], name: "index_users_on_pending_email_token", unique: true
    t.index ["personal_workspace_id"], name: "index_users_on_personal_workspace_id"
    t.index ["personal_workspace_id"], name: "index_users_on_personal_workspace_id_unique", unique: true, where: "personal_workspace_id IS NOT NULL"
    t.index ["webauthn_handle"], name: "index_users_on_webauthn_handle", unique: true
  end

  create_table "webauthn_challenges", force: :cascade do |t|
    t.string "challenge", null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "purpose", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["challenge"], name: "index_webauthn_challenges_on_challenge", unique: true
    t.index ["user_id"], name: "index_webauthn_challenges_on_user_id"
  end

  create_table "webauthn_credentials", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "discarded_at"
    t.string "external_id", null: false
    t.datetime "last_used_at"
    t.string "nickname"
    t.string "public_key", null: false
    t.integer "sign_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.datetime "verified_at"
    t.index ["external_id"], name: "index_webauthn_credentials_on_external_id", unique: true
    t.index ["user_id"], name: "index_webauthn_credentials_on_user_id"
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
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "discarded_at"
    t.string "join_policy", default: "invite", null: false
    t.string "logo_source", default: "initials", null: false
    t.integer "max_members", default: 5, null: false
    t.string "name", null: false
    t.boolean "personal", default: false, null: false
    t.string "plan", default: "free", null: false
    t.integer "primary_color", default: 210
    t.string "slug", null: false
    t.datetime "suspended_at"
    t.datetime "updated_at", null: false
    t.index ["archived_at"], name: "index_workspaces_on_archived_at"
    t.index ["discarded_at"], name: "index_workspaces_on_discarded_at"
    t.index ["join_policy"], name: "index_workspaces_on_join_policy"
    t.index ["slug"], name: "index_workspaces_on_slug", unique: true
    t.index ["suspended_at"], name: "index_workspaces_on_suspended_at"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "activity_logs", "users", column: "actor_id"
  add_foreign_key "activity_logs", "workspaces"
  add_foreign_key "authentications", "users"
  add_foreign_key "availability_blocks", "rooms"
  add_foreign_key "availability_blocks", "workspaces"
  add_foreign_key "buildings", "campuses"
  add_foreign_key "buildings", "users", column: "hidden_by_id"
  add_foreign_key "buildings", "workspaces"
  add_foreign_key "campuses", "workspaces"
  add_foreign_key "characteristic_display_rules", "workspaces"
  add_foreign_key "editor_assignments", "units"
  add_foreign_key "editor_assignments", "users"
  add_foreign_key "editor_assignments", "workspaces"
  add_foreign_key "floors", "buildings"
  add_foreign_key "floors", "workspaces"
  add_foreign_key "invitations", "roles"
  add_foreign_key "invitations", "users", column: "accepted_by_id"
  add_foreign_key "invitations", "users", column: "invited_by_id"
  add_foreign_key "memberships", "roles"
  add_foreign_key "memberships", "users"
  add_foreign_key "memberships", "workspaces"
  add_foreign_key "noticed_notifications", "noticed_events", column: "event_id", on_delete: :cascade
  add_foreign_key "roles", "workspaces"
  add_foreign_key "room_characteristics", "rooms"
  add_foreign_key "room_characteristics", "workspaces"
  add_foreign_key "room_contacts", "rooms"
  add_foreign_key "room_contacts", "workspaces"
  add_foreign_key "room_gallery_images", "rooms"
  add_foreign_key "room_gallery_images", "workspaces"
  add_foreign_key "rooms", "buildings"
  add_foreign_key "rooms", "campuses"
  add_foreign_key "rooms", "floors"
  add_foreign_key "rooms", "units"
  add_foreign_key "rooms", "users", column: "hidden_by_id"
  add_foreign_key "rooms", "workspaces"
  add_foreign_key "sessions", "users"
  add_foreign_key "sync_phases", "sync_runs"
  add_foreign_key "sync_phases", "workspaces"
  add_foreign_key "sync_runs", "workspaces"
  add_foreign_key "sync_scope_rules", "workspaces"
  add_foreign_key "unit_display_names", "workspaces"
  add_foreign_key "units", "workspaces"
  add_foreign_key "user_preferences", "users"
  add_foreign_key "users", "workspaces", column: "personal_workspace_id", on_delete: :nullify
  add_foreign_key "webauthn_challenges", "users"
  add_foreign_key "webauthn_credentials", "users"
  add_foreign_key "workspace_join_links", "users", column: "created_by_id"
  add_foreign_key "workspace_join_links", "workspaces"

  # Virtual tables defined in this database.
  # Note that virtual tables may not work with other database engines. Be careful if changing database.
  create_virtual_table "building_search_index", "fts5", ["name", "nickname", "abbreviation", "tokenize = 'unicode61'"]
  create_virtual_table "room_search_index", "fts5", ["facility_code", "nickname", "room_number", "rmrecnbr", "building_name", "tokenize = 'unicode61'"]
end
