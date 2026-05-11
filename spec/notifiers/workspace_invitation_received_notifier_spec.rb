# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkspaceInvitationReceivedNotifier, type: :notifier do
  let(:workspace) { create(:workspace) }
  let(:invited_user) { create(:user) }
  let(:inviter) { create(:user) }
  let(:invitation) do
    create(:invitation,
           invitable: workspace,
           email: invited_user.email_address,
           invited_by: inviter)
  end

  describe ".category" do
    it "is :account_access" do
      expect(described_class.category_name).to eq "account_access"
    end
  end

  describe "dispatching" do
    it "delivers to the invited user and creates a Noticed::Notification row" do
      result = described_class.with(record: invitation).deliver(invited_user)
      expect(result).to eq :delivered
      expect(invited_user.notifications.count).to eq 1
    end

    it "auto-populates idempotency_key on the event column" do
      described_class.with(record: invitation).deliver(invited_user)
      event = Noticed::Event.last
      expect(event.idempotency_key).to be_present
      expect(event.params["idempotency_key"]).to be_nil  # column, not params
    end

    it "deduplicates concurrent dispatches within the same minute" do
      freeze_time do
        described_class.with(record: invitation).deliver(invited_user)
        result = described_class.with(record: invitation).deliver(invited_user)
        expect(result).to eq :deduplicated
        expect(Noticed::Event.where(type: described_class.name).count).to eq 1
      end
    end
  end

  describe "preferences gating" do
    let!(:prefs) { create(:user_preferences, user: invited_user) }

    it "respects DND for non-security categories" do
      prefs.update!(notification_preferences:
        prefs.notification_preferences.merge("quiet_hours" => { "enabled" => true, "start" => "00:00", "end" => "23:59", "allow_urgent" => true }))
      described_class.with(record: invitation).deliver(invited_user)
      notification = invited_user.notifications.last
      expect(notification.recipient_pref(:email)).to be false
    end

    it "permits in-app + email under default preferences (account_access)" do
      described_class.with(record: invitation).deliver(invited_user)
      notification = invited_user.notifications.last
      expect(notification.recipient_pref(:in_app)).to be true
      expect(notification.recipient_pref(:email)).to be true
    end
  end
end
