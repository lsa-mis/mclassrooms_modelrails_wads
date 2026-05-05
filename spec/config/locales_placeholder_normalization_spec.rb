# frozen_string_literal: true

require "rails_helper"

# Locks the post-normalization vocabulary across the
# `notifications.<event>.message` keys (used by Notifier#message) and the
# parallel `notification_mailer.<event>.body` keys (used by the email
# templates). Both halves of each event must use the SAME placeholder name
# for the SAME concept — when the message says `%{new_role}`, the mailer
# body must say `%{new_role}` too. PR-2b shipped with the message side
# already using semantic names; this normalization brings the mailer side
# in line so a translator working on either string sees a single vocabulary.
RSpec.describe "notifications.en.yml placeholder normalization", type: :config do
  it "uses %{new_role} (not %{role}) in notification_mailer.workspace_role_changed.body" do
    body = I18n.t("notification_mailer.workspace_role_changed.body", workspace: "_", new_role: "Admin")
    expect(body).to include("Admin")
    expect(body).not_to include("%{")
  end

  it "uses %{new_role} (not %{role}) in notification_mailer.workspace_member_added.body" do
    body = I18n.t("notification_mailer.workspace_member_added.body", workspace: "_", new_role: "Member")
    expect(body).to include("Member")
    expect(body).not_to include("%{")
  end

  it "the message keys keep %{new_role} (no regression)" do
    role_changed = I18n.t("notifications.workspace_role_changed.message", workspace: "_", new_role: "Admin")
    expect(role_changed).to include("Admin")
    expect(role_changed).not_to include("%{")
  end
end
