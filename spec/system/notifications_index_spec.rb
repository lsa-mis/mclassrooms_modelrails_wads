require "rails_helper"

RSpec.describe "Notifications index page", type: :system do
  let(:password) { "SecureP@ssw0rd123!" }
  let(:user) { create(:user, password: password) }

  def sign_in_via_form(user)
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    expect(page).to have_text(I18n.t("sessions.check_email.title"))
    token = MagicLinkToken.where(email: user.email_address).order(:created_at).last.token
    visit magic_link_callback_path(token: token)
    expect(page).to have_text(I18n.t("magic_link_callbacks.show.signed_in"))
  end

  # Monotonic per-example offset: every dispatch lands 5 minutes after the
  # previous one, so each notification gets a distinct idempotency bucket
  # without relying on rand. Same pattern as
  # spec/requests/account/notifications_spec.rb. See project memory
  # `project_flaky_tests_followup.md` for the rand-bucket-collision history:
  # 1/1000 collisions would dedup-drop retries and flake "renders only unread"
  # assertions.
  def deliver_security_notification(recipient = user)
    @notification_offset ||= 0
    @notification_offset += 5
    travel_to(Time.current + @notification_offset.minutes) do
      PasswordChangedNotifier.with(record: recipient).deliver(recipient)
    end
    recipient.notifications.reload.last
  end

  before { sign_in_via_form(user) }

  describe "discoverability (v2: canonical path is the user-menu Notifications row)" do
    it "exposes a Notifications link inside the user-menu dropdown" do
      visit root_path
      find("#user-menu-button").click
      within "#user-menu" do
        expect(page).to have_link(I18n.t("navigation.notifications"), href: settings_notifications_path)
      end
    end
  end

  describe "GET /account/notifications" do
    it "renders the heading and a list row containing each notification's message" do
      notification = deliver_security_notification
      expected_message = I18n.t(
        "notifications.password_changed.message",
        user_name: user.first_name
      )

      visit settings_notifications_path

      expect(page).to have_css("h1", text: I18n.t("notifications.index.heading"))
      within "##{ActionView::RecordIdentifier.dom_id(notification)}" do
        expect(page).to have_text(expected_message)
      end
    end

    describe "filter chips" do
      it "marks the All chip as current by default" do
        deliver_security_notification

        visit settings_notifications_path

        within "[aria-label='#{I18n.t('notifications.index.filters_aria')}']" do
          expect(page).to have_link(
            I18n.t("notifications.index.filters.all"),
            href: settings_notifications_path
          )
          all_chip = find_link(I18n.t("notifications.index.filters.all"))
          expect(all_chip["aria-current"]).to eq("page")
        end
      end

      it "filters to only unread when Unread chip is followed" do
        read_notification = deliver_security_notification
        read_notification.update!(read_at: Time.current)
        unread_notification = deliver_security_notification

        visit settings_notifications_path
        click_link I18n.t("notifications.index.filters.unread")

        expect(page).to have_css("##{ActionView::RecordIdentifier.dom_id(unread_notification)}")
        expect(page).not_to have_css("##{ActionView::RecordIdentifier.dom_id(read_notification)}")
      end
    end

    describe "per-row controls" do
      it "marks an unread row as read via Turbo Stream and swaps the button" do
        notification = deliver_security_notification

        visit settings_notifications_path

        within "##{ActionView::RecordIdentifier.dom_id(notification)}" do
          click_button I18n.t("notifications.index.item.mark_read")
          expect(page).to have_button(I18n.t("notifications.index.item.mark_unread"))
        end
        expect(notification.reload.read_at).to be_present
      end

      it "marks a read row as unread via Turbo Stream" do
        notification = deliver_security_notification
        notification.update!(read_at: Time.current)

        visit settings_notifications_path

        within "##{ActionView::RecordIdentifier.dom_id(notification)}" do
          click_button I18n.t("notifications.index.item.mark_unread")
          expect(page).to have_button(I18n.t("notifications.index.item.mark_read"))
        end
        expect(notification.reload.read_at).to be_nil
      end

      it "deletes a row when Delete is clicked" do
        notification = deliver_security_notification

        visit settings_notifications_path
        within "##{ActionView::RecordIdentifier.dom_id(notification)}" do
          click_button I18n.t("notifications.index.item.delete")
        end

        expect(page).not_to have_css("##{ActionView::RecordIdentifier.dom_id(notification)}")
      end
    end

    describe "bulk actions" do
      it "marks every unread notification as read after confirming the bulk modal" do
        unread_a = deliver_security_notification
        unread_b = deliver_security_notification

        visit settings_notifications_path
        click_button I18n.t("notifications.index.mark_all_read.action")
        within "dialog[open]" do
          click_button I18n.t("notifications.index.mark_all_read.action")
        end

        expect(page).to have_text(I18n.t("notifications.index.mark_all_read.success"))
        expect(unread_a.reload.read_at).to be_present
        expect(unread_b.reload.read_at).to be_present
      end

      it "deletes every read notification after confirming the bulk modal" do
        read_a = deliver_security_notification
        read_a.update!(read_at: Time.current)
        read_b = deliver_security_notification
        read_b.update!(read_at: Time.current)
        read_ids = [ read_a.id, read_b.id ]

        visit settings_notifications_path
        click_button I18n.t("notifications.index.destroy_all_read.action")
        within "dialog[open]" do
          click_button I18n.t("notifications.index.destroy_all_read.action")
        end

        expect(page).to have_text(I18n.t("notifications.index.destroy_all_read.success"))
        expect(Noticed::Notification.where(id: read_ids).count).to eq(0)
      end
    end

    # axe-core WCAG 2.2 AAA on the populated index page is not asserted
    # directly here — `members_table_spec.rb` audits the same workspace-
    # branded surface stack with stricter `DEFERRED_AAA_EXCLUDES` (the
    # durable two-variable `--ws-primary-light`/`--ws-primary-dark` scheme
    # took `.text-interactive` and `.bg-interactive` out of the umbrella),
    # making it the canary for any future cascade-induced surface drift.
  end
end
