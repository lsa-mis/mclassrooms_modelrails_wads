# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Account Notifications", type: :request do
  # D11: an unread item is the only one that needs attention, so it should not
  # be pushed off the page by newer read ones.
  describe "GET /settings/notifications ordering" do
    let(:reader) { create(:user) }

    def deliver_to(reader)
      before = reader.notifications.pluck(:id)
      PasswordChangedNotifier.with(record: reader, idempotency_key: SecureRandom.hex(8)).deliver(reader)
      reader.notifications.where.not(id: before).sole
    end

    it "orders unread first, then newest, so an older unread outranks a newer read one" do
      # Sign in first: the sign-in itself writes a new-device notification, and
      # creating fixtures after it keeps that row out of the ids under test.
      sign_in(reader)
      older_unread = travel_to(2.hours.ago) { deliver_to(reader) }
      newer_read   = travel_to(1.hour.ago)  { deliver_to(reader) }
      newer_read.update!(read_at: Time.current)

      get settings_notifications_path

      rendered = Nokogiri::HTML(response.body)
        .css("li[id]").map { |el| el["id"][/_notification_(\d+)\z/, 1]&.to_i }.compact

      # Relative order of the two under test — newest-first alone would put the
      # read one ahead of the older unread one.
      expect(rendered & [ older_unread.id, newer_read.id ])
        .to eq([ older_unread.id, newer_read.id ])
    end
  end

  describe "unauthenticated access" do
    it "redirects GET /account/notifications to sign in" do
      get settings_notifications_path
      expect(response).to redirect_to(new_session_path)
    end

    it "redirects POST /account/notification_readings (mark all read) to sign in" do
      post settings_notification_readings_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    let(:user) { create(:user) }
    let(:other_user) { create(:user) }

    before { sign_in(user) }

    # Dispatches a real notifier so the message body, recipient association,
    # idempotency key — everything the index renders — is exactly what
    # production builds. Using PasswordChangedNotifier (security category)
    # for the default; tests that need account_access dispatch their own.
    def deliver_security_notification(recipient = user)
      deliver_in_distinct_idempotency_bucket do
        PasswordChangedNotifier.with(record: recipient).deliver(recipient)
      end
      recipient.notifications.reload.last
    end

    def deliver_account_access_notification(recipient: user, inviter: nil)
      inviter ||= create(:user)
      workspace = create(:workspace)
      invitation = create(:invitation,
                          invitable: workspace,
                          email: "x#{SecureRandom.hex(4)}@example.com",
                          invited_by: inviter)
      deliver_in_distinct_idempotency_bucket do
        WorkspaceInvitationResentNotifier.with(record: invitation).deliver(recipient)
      end
      recipient.notifications.reload.last
    end

    # A same-bucket collision dedup-drops the 2nd dispatch and flaked the
    # "renders only unread" assertion.
    def deliver_in_distinct_idempotency_bucket(&block)
      @notification_offset = (@notification_offset || 0) + 5
      travel_to(Time.current + @notification_offset.minutes, &block)
    end

    def dom_id_fragment(notification)
      "id=\"#{ActionView::RecordIdentifier.dom_id(notification)}\""
    end

    describe "GET /account/notifications" do
      it "returns 200 and renders the index" do
        deliver_security_notification
        get settings_notifications_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("notifications.index.heading"))
      end

      # The missing-row default can't be proven through a system spec: the
      # timezone beacon (layout-level Stimulus, JS-only) creates a
      # preferences row on every real-browser sign-in before any assertion
      # can run. This request spec's sign_in helper never touches JS, so the
      # row genuinely stays absent — the one place this contract holds.
      it "states the default retention for a user with no preferences row" do
        expect(user.preferences).to be_nil

        get settings_notifications_path

        expect(response.body).to include("we remove it 90 days later")
      end

      # The period label is a dynamic key with no inline default, so the label
      # set and the allowed set must agree: a fork widening
      # ALLOWED_RETENTION_DAYS adds the label here or this example is red.
      # (The value object refuses any value outside the set, so a stored row
      # cannot name a value that has no label.)
      it "labels every allowed retention value" do
        unlabeled = NotificationPreferences::ALLOWED_RETENTION_DAYS.reject do |days|
          I18n.exists?("notifications.preferences.advanced.retention_options.#{days}")
        end
        expect(unlabeled).to be_empty, "retention values without a retention_options label: #{unlabeled.join(", ")}"
      end

      # Regression (Bullet unused-eager-loading). The index eager-loads
      # `event: :record` because ~10 of the 12 notifier `#message` impls read it
      # (workspace/invitation/password). SignInFromNewDevice's `#message` is
      # params-only, so an index of ONLY device notifications never touches
      # `record` — Bullet (raise=true in test) flagged the preload as unused.
      # The preload is correct (it prevents an N+1 for the common case); the
      # device-only page is the data-dependent false positive we safelist.
      it "renders an index of only device-sign-in notifications without tripping Bullet" do
        SignInFromNewDeviceNotifier
          .with(record: user, user_agent: "Mozilla/5.0", os: "macOS")
          .deliver(user)
        expect(user.notifications.reload).to be_present
        get settings_notifications_path
        expect(response).to have_http_status(:ok)
      end

      it "scopes to the current user (own notifications visible, others' not)" do
        own = deliver_security_notification
        foreign = deliver_security_notification(other_user)
        # Sign-in detection itself dispatches a SignInFromNewDeviceNotifier
        # to the current user, so the user's notifications list is non-empty
        # by the time this request fires. Assert specifically that:
        #   1. the user's OWN dispatched notification IS rendered (positive),
        #   2. the foreign user's notification is NOT rendered.
        # The positive assertion guards against a future regression where the
        # index breaks rendering for legitimate recipients but coincidentally
        # still hides foreign rows.
        get settings_notifications_path
        expect(response.body).to include(dom_id_fragment(own))
        expect(response.body).not_to include(dom_id_fragment(foreign))
        expect(response).to have_http_status(:ok)
      end

      it "paginates with Pagy at 25 per page" do
        # Create 30 notifications via direct insert (faster than dispatch).
        event = Noticed::Event.create!(type: "PasswordChangedNotifier", params: {}, record: user)
        notifications = Array.new(30) do
          Noticed::Notification.create!(
            event: event,
            recipient: user,
            type: "PasswordChangedNotifier::Notification"
          )
        end
        get settings_notifications_path
        rendered = notifications.count { |n| response.body.include?(dom_id_fragment(n)) }
        # Sign-in detection adds 1 user notification on the way in, so first
        # page may include 24 of our 30 + the sign-in notification — still 25
        # total on the page. Assert at least 24 of our 30 rendered (Pagy caps
        # the page at 25 rows).
        expect(rendered).to be >= 24
        expect(rendered).to be <= 25
      end

      # #763 (1.3.1): read-vs-unread was carried only by a font-weight class,
      # and the timestamp read "3 hours" with no "ago" (the <time datetime>
      # attribute is not announced). The row must open with an sr-only status
      # and the timestamp must be the wrapped, localized "ago" form.
      it "conveys read state and a complete timestamp to assistive tech" do
        read_notification = deliver_security_notification
        read_notification.update!(read_at: Time.current)
        unread_notification = deliver_security_notification

        get settings_notifications_path
        page = Capybara.string(response.body)

        within_read = page.find("##{ActionView::RecordIdentifier.dom_id(read_notification)}")
        within_unread = page.find("##{ActionView::RecordIdentifier.dom_id(unread_notification)}")

        expect(within_unread).to have_css(".sr-only", text: I18n.t("notifications.index.item.status_unread"))
        expect(within_read).to have_css(".sr-only", text: I18n.t("notifications.index.item.status_read"))
        [ within_read, within_unread ].each do |row|
          expect(row.find("time").text.strip).to end_with("ago")
        end
      end

      context "?filter=unread" do
        it "renders only unread notifications" do
          read_notification = deliver_security_notification
          read_notification.update!(read_at: Time.current)
          unread_notification = deliver_security_notification

          get settings_notifications_path, params: { filter: "unread" }
          expect(response.body).to include(dom_id_fragment(unread_notification))
          expect(response.body).not_to include(dom_id_fragment(read_notification))
        end
      end

      context "?category=security" do
        it "renders only notifications for that category" do
          security_notification = deliver_security_notification
          access_notification = deliver_account_access_notification(recipient: user)

          get settings_notifications_path, params: { category: "security" }
          expect(response.body).to include(dom_id_fragment(security_notification))
          expect(response.body).not_to include(dom_id_fragment(access_notification))
        end
      end

      describe "SR aria-labels on per-row buttons" do
        # A SR navigating button-to-button on the index would otherwise hear
        # "Mark as read button … Mark as read button …" with no way to tell
        # which notification each refers to. aria-label adds the message as
        # the label so each button announces its target.
        it "the Mark-as-read button includes the notification's message in its aria-label" do
          notification = deliver_security_notification
          get settings_notifications_path
          expected = I18n.t(
            "notifications.index.item.mark_read_aria",
            summary: notification.message
          )
          expect(response.body).to include(%Q(aria-label="#{expected}"))
        end

        it "the Mark-as-unread button includes the notification's message when the row is read" do
          notification = deliver_security_notification
          notification.update!(read_at: Time.current)
          get settings_notifications_path
          expected = I18n.t(
            "notifications.index.item.mark_unread_aria",
            summary: notification.message
          )
          expect(response.body).to include(%Q(aria-label="#{expected}"))
        end
      end
    end

    describe "PATCH /account/notifications/:id" do
      let!(:notification) { deliver_security_notification }

      it "marks the notification as read when read_at is set" do
        patch settings_notification_path(notification), params: { read_at: "now" }
        expect(notification.reload.read_at).to be_present
      end

      it "marks the notification as unread when read_at is blank" do
        notification.update!(read_at: Time.current)
        patch settings_notification_path(notification), params: { read_at: "" }
        expect(notification.reload.read_at).to be_nil
      end

      it "redirects via the ApplicationController not-found rescue for another user's notification" do
        foreign = deliver_security_notification(other_user)
        patch settings_notification_path(foreign), params: { read_at: "now" }
        # set_notification scopes through Current.user.notifications.find,
        # so a foreign id raises ActiveRecord::RecordNotFound — rescued by
        # ApplicationController#record_not_found which redirects HTML format
        # to request.referer || root_path with the not_found alert.
        expect(response).to have_http_status(:redirect)
        expect(flash[:alert]).to eq(I18n.t("errors.not_found"))
        expect(foreign.reload.read_at).to be_nil
      end

      # Focus management on Turbo Stream replace: when the row is replaced
      # in-place, the original button no longer exists in the DOM and focus
      # is lost. The replaced row autofocuses the now-visible toggle (the
      # opposite-state button), so keyboard/SR users land back on the same
      # logical control instead of being thrown to <body>.
      it "the turbo_stream response autofocuses the toggle button on the replaced row" do
        patch settings_notification_path(notification, read_at: "now"),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

        # Exactly one autofocus attribute lands in the response — the
        # opposite-state toggle (Mark-as-unread, since the row is now read).
        # `autofocus="autofocus"` is Rails' boolean-attribute serialization;
        # match against the attribute form to avoid double-counting against
        # the literal string "autofocus" appearing as both name and value.
        autofocus_count = response.body.scan(/autofocus="autofocus"/).size
        expect(autofocus_count).to eq(1)
        expect(response.body).to include(I18n.t("notifications.index.item.mark_unread"))
      end
    end

    # Marking everything read is the create of readings for all notifications (#1007),
    # the bulk twin of Settings::Notifications::ReadingsController.
    describe "POST /account/notification_readings" do
      it "marks ALL of the current user's unread notifications as read (250-row behavior assertion)" do
        # Build 250 unread notifications without going through the notifier
        # (faster + avoids idempotency collisions). We assert the OUTCOME —
        # all 250 rows have read_at set after the request — not the
        # implementation detail (single update_all vs. batched).
        event = Noticed::Event.create!(type: "PasswordChangedNotifier", params: {}, record: user)
        notifications = Array.new(250) do
          Noticed::Notification.create!(
            event: event,
            recipient: user,
            type: "PasswordChangedNotifier::Notification"
          )
        end

        post settings_notification_readings_path

        unread_remaining = user.notifications.where(read_at: nil).count
        expect(unread_remaining).to eq(0)
        expect(notifications.first.reload.read_at).to be_present
        expect(notifications.last.reload.read_at).to be_present
      end

      it "does not affect other users' unread notifications" do
        foreign_event = Noticed::Event.create!(type: "PasswordChangedNotifier", params: {}, record: other_user)
        foreign = Noticed::Notification.create!(
          event: foreign_event,
          recipient: other_user,
          type: "PasswordChangedNotifier::Notification"
        )

        post settings_notification_readings_path

        expect(foreign.reload.read_at).to be_nil
      end

      it "redirects with a success notice" do
        post settings_notification_readings_path
        expect(response).to redirect_to(settings_notifications_path)
        expect(flash[:notice]).to eq(I18n.t("settings.notification_readings.create.success"))
      end
    end

    # Cross-tab read-state sync: every read-state mutation must broadcast all
    # THREE frame targets (avatar dot, hamburger dot, menu count) on the
    # `[user, :notifications]` channel — the mutating tab's own surfaces come
    # from the direct response; broadcasts cover every other tab.
    # See /docs/developer/notifications.
    describe "cross-tab read-state sync (v2 avatar/hamburger/menu broadcasts)" do
      let(:notification) { deliver_security_notification }

      # Helper: assert that all three v2 broadcast targets fire. The v2
      # broadcaster (lib/notification_broadcaster.rb) fans out to avatar,
      # hamburger, and menu-count frames on every refresh.
      def expect_v2_refresh_broadcasts
        # All surfaces use broadcast_update_to (the frame ones keep the
        # <turbo-frame> addressable across refreshes); allow the aria-live one so
        # the three frame expectations below are the only constraints.
        allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)
        expect(Turbo::StreamsChannel).to receive(:broadcast_update_to)
          .with([ user, :notifications ], hash_including(target: "notifications_indicator_avatar"))
        expect(Turbo::StreamsChannel).to receive(:broadcast_update_to)
          .with([ user, :notifications ], hash_including(target: "notifications_indicator_hamburger"))
        expect(Turbo::StreamsChannel).to receive(:broadcast_update_to)
          .with([ user, :notifications ], hash_including(target: "notifications_menu_count_frame"))
      end

      it "broadcasts the v2 refresh trio on PATCH (mark single notification read)" do
        notification # ensure dispatched
        expect_v2_refresh_broadcasts

        patch settings_notification_path(notification), params: { read_at: "now" }
      end

      it "broadcasts the v2 refresh trio on POST notification_readings (mark all read)" do
        notification
        expect_v2_refresh_broadcasts

        post settings_notification_readings_path
      end

      # #686: open-and-mark-read is a POST-only resource (reading) — the old
      # GET :open mutated, so link prefetchers and mail scanners marked
      # notifications read.
      it "broadcasts the v2 refresh trio on POST reading (notification-open from triage)" do
        notification
        expect_v2_refresh_broadcasts

        post settings_notification_reading_path(notification)
      end

      it "does NOT broadcast on POST reading when notification is already read (idempotent no-op)" do
        notification.update!(read_at: 1.hour.ago)

        expect(Turbo::StreamsChannel).not_to receive(:broadcast_replace_to)
        expect(Turbo::StreamsChannel).not_to receive(:broadcast_update_to)

        post settings_notification_reading_path(notification)
      end

      it "marks read and forwards to the notifier's URL" do
        post settings_notification_reading_path(notification)

        expect(notification.reload.read_at).to be_present
        expect(response).to have_http_status(:redirect)
      end

      it "no longer routes the mutating GET /:id/open" do
        get "/settings/notifications/#{notification.id}/open"

        expect(response).to have_http_status(:not_found)
        expect(notification.reload.read_at).to be_nil
      end

      # v2 (2026-05-23): the menu-count broadcast was restored. The user-menu
      # Notifications row carries a live aria-announced count badge, so every
      # read-state mutation that affects unread count refreshes
      # notifications_menu_count_frame too.
      it "DOES broadcast to notifications_menu_count_frame on read-state mutations (v2)" do
        notification

        allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)

        expect(Turbo::StreamsChannel).to receive(:broadcast_update_to)
          .with(anything, hash_including(target: "notifications_menu_count_frame"))

        patch settings_notification_path(notification), params: { read_at: "now" }
      end

      # SR parity with new-arrival broadcasts: ApplicationNotifier announces
      # arrivals via the page-level aria-live region (#notifications-live).
      # Without an equivalent announcement on read-state changes, SR users
      # in Tab B would see Tab A's mark/destroy happen silently. This
      # closes that gap.
      it "broadcasts a read-state aria-live announcement on PATCH (mark read)" do
        notification

        allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)
        expect(Turbo::StreamsChannel).to receive(:broadcast_update_to)
          .with([ user, :notifications ],
                target: "notifications-live",
                content: I18n.t("notifications.bell.read_state_announcement"))

        patch settings_notification_path(notification), params: { read_at: "now" }
      end

      it "broadcasts a read-state aria-live announcement on POST notification_readings (mark all read)" do
        notification

        allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)
        expect(Turbo::StreamsChannel).to receive(:broadcast_update_to)
          .with([ user, :notifications ],
                target: "notifications-live",
                content: I18n.t("notifications.bell.read_state_announcement"))

        post settings_notification_readings_path
      end
    end
  end
end
