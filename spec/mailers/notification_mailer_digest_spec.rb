# frozen_string_literal: true

require "rails_helper"

RSpec.describe NotificationMailer, type: :mailer do
  describe "#digest" do
    let(:user) { create(:user) }
    let(:invited_by) { create(:user) }
    let(:workspace) { create(:workspace) }

    before do
      user.create_preferences!(timezone: "UTC")
    end

    def deliver_workspace_invitation_accepted
      invitation = create(:invitation, invitable: workspace,
                          email: user.email_address, invited_by: invited_by)
      WorkspaceInvitationAcceptedNotifier.with(record: invitation).deliver(user)
      user.notifications.last
    end

    context "subject reflects digest cadence" do
      it "uses the daily subject when cadence is daily" do
        notification = deliver_workspace_invitation_accepted
        mail = described_class.digest(user, [ notification ])

        expect(mail.subject).to include("daily")
      end

      it "uses the weekly subject when cadence is weekly" do
        prefs = user.preferences.notification_preferences
        user.preferences.update!(
          notification_preferences: prefs.deep_merge("digest" => { "cadence" => "weekly" })
        )
        notification = deliver_workspace_invitation_accepted
        mail = described_class.digest(user, [ notification ])

        expect(mail.subject).to include("weekly")
      end
    end

    context "body content" do
      it "addresses the email to the user" do
        notification = deliver_workspace_invitation_accepted
        mail = described_class.digest(user, [ notification ])

        expect(mail.to).to eq([ user.email_address ])
      end

      it "groups notifications under their category heading" do
        notification = deliver_workspace_invitation_accepted
        mail = described_class.digest(user, [ notification ])

        # WorkspaceInvitationAcceptedNotifier is workspace_activity category.
        expect(mail.body.encoded).to include(
          I18n.t("notifications.preferences.categories.workspace_activity")
        )
      end

      it "renders each notification's message text" do
        notification = deliver_workspace_invitation_accepted
        eager = user.notifications.includes(event: :record).find(notification.id)
        expected_text = eager.render_safe_or_placeholder { eager.message }
        mail = described_class.digest(user, [ notification ])

        expect(mail.body.encoded).to include(expected_text)
      end

      it "includes the per-notification destination URL when available" do
        notification = deliver_workspace_invitation_accepted
        eager = user.notifications.includes(event: :record).find(notification.id)
        expected_url = eager.render_safe_or_placeholder { eager.url }
        mail = described_class.digest(user, [ notification ])

        expect(mail.body.encoded).to include(expected_url)
      end

      it "footer links to the notification-preferences page" do
        notification = deliver_workspace_invitation_accepted
        mail = described_class.digest(user, [ notification ])

        expect(mail.body.encoded).to include("notification_preferences")
      end
    end
  end
end
