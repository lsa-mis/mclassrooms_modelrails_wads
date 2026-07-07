require "rails_helper"

RSpec.describe "Notifier severity assignments" do
  expected = {
    PasswordChangedNotifier              => :danger,
    SignInFromNewDeviceNotifier          => :danger,
    WorkspaceCapacityApproachingNotifier => :warning,
    WorkspaceInvitationExpiringSoonNotifier => :warning,
    WorkspaceInvitationReceivedNotifier  => :info,
    WorkspaceInvitationResentNotifier    => :info,
    WorkspaceRoleChangedNotifier         => :info,
    WorkspaceMemberAddedNotifier         => :success,
    WorkspaceInvitationAcceptedNotifier  => :success,
    WorkspaceInvitationDeclinedNotifier  => :info
  }

  expected.each do |notifier_class, severity|
    it "#{notifier_class.name} declares severity #{severity.inspect}" do
      expect(notifier_class.severity_name).to eq(severity)
    end
  end
end
