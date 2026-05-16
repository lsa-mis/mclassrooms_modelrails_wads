# The test environment is used exclusively to run your application's
# test suite. You never need to work with it directly. Remember that
# your test database is "scratch space" for the test suite and is wiped
# and recreated between test runs. Don't rely on the data there!

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # While tests run files are not watched, reloading is not necessary.
  config.enable_reloading = false

  # Eager loading loads your entire application. When running a single test locally,
  # this is usually not necessary, and can slow down your test suite. However, it's
  # recommended that you enable it in continuous integration systems to ensure eager
  # loading is working properly before deploying your code.
  config.eager_load = ENV["CI"].present?

  # Configure public file server for tests with cache-control for performance.
  config.public_file_server.headers = { "cache-control" => "public, max-age=3600" }

  # Show full error reports.
  config.consider_all_requests_local = true
  config.cache_store = :null_store

  # Render exception templates for rescuable exceptions and raise for other exceptions.
  config.action_dispatch.show_exceptions = :rescuable

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  # Store uploaded files on the local file system in a temporary directory.
  config.active_storage.service = :test

  # Use the test queue adapter so have_enqueued_job/have_enqueued_mail
  # matchers can inspect the queue deterministically.
  config.active_job.queue_adapter = :test

  # Tell Action Mailer not to deliver emails to the real world.
  # The :test delivery method accumulates sent emails in the
  # ActionMailer::Base.deliveries array.
  config.action_mailer.delivery_method = :test

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: "localhost", port: 3000 }

  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr

  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true

  # Raise error when a before_action's only/except options reference missing actions.
  config.action_controller.raise_on_missing_callback_actions = true

  # Bullet: raise on N+1 queries in tests
  # CSP is enforced in development/production (via the initializer) but
  # report-only in test. System specs inject HTML via execute_script and
  # Playwright doesn't forward CSP nonces — enforcing here would block
  # Stimulus/importmap loading in specs without adding security value.
  config.content_security_policy_report_only = true

  config.after_initialize do
    Bullet.enable = true
    Bullet.raise = true
    # ActiveStorage uses includes(:record) internally when touch_attachment_records is true.
    # When a blob is updated, touch_attachments runs with includes(:record) for bulk SQL touch.
    # Bullet incorrectly flags this as avoidable eager loading since the touch is via SQL,
    # not Ruby object access. Safelist to avoid false positives from the framework.
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "ActiveStorage::Attachment", association: :record)

    # DELIVERY-LAYER ONLY: Noticed v2's EventJob iterates `event.notifications.each`
    # and accesses each notification's `recipient` (for the deliver_by :email
    # lambda's `recipient_pref` check, and for the Email delivery's params hash).
    # The library doesn't expose a hook to eager-load `:recipient` on the
    # notifications relation, so this is a structural constraint of the gem.
    #
    # Note: this safelist DOES NOT cover the recipients-resolver layer; that
    # layer eager-loads users explicitly with `.includes(:user)` in
    # WorkspaceMemberAddedNotifier#recipients. If a future Notifier introduces
    # a resolver-layer N+1 it will trip Bullet correctly — only the
    # delivery-iteration path under EventJob is whitelisted.
    Bullet.add_safelist(type: :n_plus_one_query,
                        class_name: "WorkspaceMemberAddedNotifier::Notification",
                        association: :recipient)

    # Same delivery-layer rationale as WorkspaceMemberAddedNotifier above —
    # WorkspaceCapacityApproachingNotifier dispatches to all workspace owners,
    # and Noticed iterates each notification to apply the `:email` deliver_by
    # `before_enqueue` lambda (which calls `recipient_pref`).
    Bullet.add_safelist(type: :n_plus_one_query,
                        class_name: "WorkspaceCapacityApproachingNotifier::Notification",
                        association: :recipient)

    # /account/notifications eager-loads `event.record` for every row via
    # `includes(:recipient, event: :record)` in `Account::NotificationsController#index`,
    # because every other notifier subtype's `#message` interpolates
    # `event.record.<attr>`. SignInFromNewDeviceNotifier is the lone
    # exception — its `#message` only reads `event.params` — so when it's
    # the only subtype in the result the `:record` include is unused and
    # Bullet flags AVOID. Safelist documents the deliberate trade-off
    # rather than dropping eager-load for all rows.
    Bullet.add_safelist(type: :unused_eager_loading,
                        class_name: "SignInFromNewDeviceNotifier",
                        association: :record)

    # /account/notifications can render up to a full page of notifications
    # across mixed notifier subtypes. WorkspaceMemberAddedNotifier traverses
    # `event.record.user.first_name` (record is a Membership), which Rails'
    # polymorphic `includes(event: :record)` can't transitively eager-load
    # without a per-subtype preload step. Accepting the N+1 on this page
    # is the right trade-off versus a per-subtype preload pipeline.
    Bullet.add_safelist(type: :n_plus_one_query,
                        class_name: "Membership",
                        association: :user)
    Bullet.add_safelist(type: :n_plus_one_query,
                        class_name: "Membership",
                        association: :workspace)
    # Same polymorphic-deep-include rationale: WorkspaceInvitationAcceptedNotifier
    # traverses `event.record.accepted_by` and `event.record.invitable` (record
    # is an Invitation) when rendering its `#message` on the notifications
    # index page.
    Bullet.add_safelist(type: :n_plus_one_query,
                        class_name: "Invitation",
                        association: :accepted_by)
    Bullet.add_safelist(type: :n_plus_one_query,
                        class_name: "Invitation",
                        association: :invitable)
  end
end
