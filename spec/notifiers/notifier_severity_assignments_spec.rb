require "rails_helper"

RSpec.describe "Notifier severity assignments" do
  expected = {
    PasswordChangedNotifier              => :danger,
    PasskeyAddedNotifier                 => :danger,
    SignInFromNewDeviceNotifier          => :danger,
    WorkspaceCapacityApproachingNotifier => :warning,
    WorkspaceInvitationExpiringSoonNotifier => :warning,
    WorkspaceInvitationResentNotifier    => :info,
    WorkspaceRoleChangedNotifier         => :info,
    WorkspaceCreatedNotifier             => :success,
    WorkspaceJoinedNotifier              => :success,
    WorkspaceMemberAddedNotifier         => :success,
    WorkspaceMemberRemovedNotifier       => :warning,
    WorkspaceInvitationAcceptedNotifier  => :success,
    WorkspaceInvitationDeclinedNotifier  => :info,
    WelcomeNotifier                      => :info
  }

  expected.each do |notifier_class, severity|
    it "#{notifier_class.name} declares severity #{severity.inspect}" do
      expect(notifier_class.severity_name).to eq(severity)
    end
  end

  # Without this, the roster above only checks the notifiers it already knows
  # about: a new one that forgets `severity` silently takes ApplicationNotifier's
  # :info default and no example ever names it. Same on-disk sync its sibling
  # spec/requests/settings/notifications_record_preloads_spec.rb runs.
  it "keeps the roster in sync with app/notifiers" do
    on_disk = Dir[Rails.root.join("app/notifiers/*_notifier.rb").to_s]
      .map { File.basename(_1, ".rb").camelize }
      .reject { _1 == "ApplicationNotifier" }

    expect(expected.keys.map(&:name)).to match_array(on_disk)
  end
end
