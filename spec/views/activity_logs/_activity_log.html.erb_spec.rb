# frozen_string_literal: true

require "rails_helper"

# Three bugs met on this partial.
#
# #911: every key under `activity.actions` was written flat and dotted
# ("membership.created:"), which I18n's nested lookup never finds — so the
# `default:` fired on every row and the feed rendered humanized column values
# ("Membership.updated").
#
# #932: a deactivation and a reactivation are both recorded as
# `membership.updated`, so even with resolving keys they read as role changes.
# The row's own `changes` metadata is what distinguishes them.
#
# Fix round 1: the row's SUBJECT is its actor (Trackable writes
# `actor: Current.user`), so "was deactivated" attached the removal to whoever
# performed it — "Ada Owner was deactivated" when Ada removed Dee. Membership
# copy now names the actor as subject and the member as OBJECT, and a
# self-removal reads as a departure instead.
RSpec.describe "activity_logs/_activity_log", type: :view do
  def render_row(action:, metadata: {}, actor: nil, trackable: nil)
    log = ActivityLog.new(
      action: action,
      metadata: metadata,
      actor: actor,
      trackable: trackable,
      created_at: Time.current
    )
    render partial: "activity_logs/activity_log", locals: { activity_log: log }
    rendered
  end

  def deactivation_metadata
    { "changes" => { "discarded_at" => [ nil, 1.minute.ago.iso8601 ] } }
  end

  # `normalize_ws:` throughout this block: the subject and the object live in
  # two sibling <span>s, so the rendered text carries the markup's newlines
  # between them and an un-normalized match never sees the sentence.
  describe "who the row is about" do
    let(:workspace) { create(:workspace) }
    let(:ada) { create(:user, first_name: "Ada", last_name: "Owner") }
    let(:dee) { create(:user, first_name: "Dee", last_name: "Member") }
    let(:dees_membership) { create(:membership, user: dee, workspace: workspace) }

    it "names the actor as subject and the removed member as object" do
      html = render_row(
        action: "membership.updated",
        metadata: deactivation_metadata,
        actor: ada,
        trackable: dees_membership
      )

      expect(html).to have_text("Ada Owner deactivated Dee Member", normalize_ws: true)
    end

    it "reads as a departure when the actor is the member themselves" do
      html = render_row(
        action: "membership.updated",
        metadata: deactivation_metadata,
        actor: dee,
        trackable: dees_membership
      )

      expect(html).to have_text("Dee Member left the workspace", normalize_ws: true)
      expect(html).not_to have_text("deactivated")
    end

    it "names the member as object on a reactivation" do
      html = render_row(
        action: "membership.updated",
        metadata: { "changes" => { "discarded_at" => [ 1.minute.ago.iso8601, nil ] } },
        actor: ada,
        trackable: dees_membership
      )

      expect(html).to have_text("Ada Owner reactivated Dee Member", normalize_ws: true)
    end

    it "names whose role changed" do
      html = render_row(
        action: "membership.updated",
        metadata: { "changes" => { "role" => [ "member", "admin" ] } },
        actor: ada,
        trackable: dees_membership
      )

      expect(html).to have_text("Ada Owner changed Dee Member's role", normalize_ws: true)
    end

    # The membership outlives the removal it records, so the row must not be
    # scoped away — but the row also outlives a hard-deleted membership.
    it "still names the member when their membership is discarded" do
      dees_membership.deactivate!(removed_by: ada)

      html = render_row(
        action: "membership.updated",
        metadata: deactivation_metadata,
        actor: ada,
        trackable: dees_membership
      )

      expect(html).to have_text("Ada Owner deactivated Dee Member", normalize_ws: true)
    end

    it "falls back to a neutral noun when the membership is gone" do
      html = render_row(
        action: "membership.updated",
        metadata: deactivation_metadata,
        actor: ada,
        trackable: nil
      )

      expect(html).to have_text("Ada Owner deactivated a member", normalize_ws: true)
    end
  end

  describe "membership.updated" do
    it "reads as a deactivation when discarded_at was set" do
      html = render_row(action: "membership.updated", metadata: deactivation_metadata)

      expect(html).to have_text("deactivated")
      expect(html).not_to have_text("role")
    end

    it "reads as a reactivation when discarded_at was cleared" do
      html = render_row(
        action: "membership.updated",
        metadata: { "changes" => { "discarded_at" => [ 1.minute.ago.iso8601, nil ] } }
      )

      expect(html).to have_text("reactivated")
    end

    it "reads as a role change when only the role moved" do
      html = render_row(
        action: "membership.updated",
        metadata: { "changes" => { "role" => [ "member", "admin" ] } }
      )

      expect(html).to have_text("role")
    end

    # #932: reactivate! can carry a role, and losing or regaining access is the
    # more consequential half of such a row.
    it "lets the status change win when the row carries both" do
      html = render_row(
        action: "membership.updated",
        metadata: { "changes" => {
          "role" => [ "member", "admin" ],
          "discarded_at" => [ nil, 1.minute.ago.iso8601 ]
        } }
      )

      expect(html).to have_text("deactivated")
      expect(html).not_to have_text("role")
    end
  end

  it "renders the written string for membership.created" do
    expect(render_row(action: "membership.created")).to have_text("joined the workspace")
  end

  it "renders the written string for a non-membership action" do
    expect(render_row(action: "project.created")).to have_text("created a project")
  end

  # No fallback: an action without a label is a missing translation, which
  # raises in test. spec/code_smells/dynamic_i18n_keys_have_values_spec.rb is
  # the gate that keeps every action the feed can render labeled.
  it "has no humanized fallback for an unlabeled action" do
    expect { render_row(action: "widget.frobnicated") }.to raise_error(ActionView::Template::Error, /translation missing/i)
  end

  # The #911 pin: the strings above must come from the locale file with no
  # `default:` masking a miss.
  it "sources its copy from resolvable locale keys" do
    expect(I18n.t("activity.actions.membership.created")).to eq("joined the workspace")
    expect(I18n.t("activity.actions.membership.updated", member: "Dee")).to eq("changed Dee's role")
    expect(I18n.t("activity.actions.membership.deactivated", member: "Dee")).to eq("deactivated Dee")
    expect(I18n.t("activity.actions.membership.reactivated", member: "Dee")).to eq("reactivated Dee")
    expect(I18n.t("activity.actions.membership.left")).to eq("left the workspace")
    expect(I18n.t("activity.unknown_member")).to eq("a member")
    expect(I18n.t("activity.actions.project.created")).to eq("created a project")
  end
end
