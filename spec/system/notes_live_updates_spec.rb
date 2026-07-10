require "rails_helper"

# MiClassrooms Phase 5 Task 10 (Brief §14.1, D15): live-update coverage for
# Note's Broadcastable wiring (app/models/note.rb#broadcast_changes) on the
# room detail page, plus axe AAA with the note create form open.
#
# Two independent Capybara/Playwright sessions (`using_session`), per the
# brief's PREFERRED shape: session A (the room's unit editor) authors an
# alert note, replies to it, and destroys the reply; session B (a second,
# merely-viewing member who never submits anything) watches the SAME room
# page the whole time and must see every change land WITHOUT reloading.
#
# This is genuinely real delivery, not a simulated stand-in: config/cable.yml
# sets `test: { adapter: test }`, and ActionCable::SubscriptionAdapter::Test
# (actioncable 8.1.3) is documented as "extend[ing] the Async adapter, so it
# could be used in system tests too" — its #broadcast records the payload
# for `have_broadcasted_to`-style assertions AND THEN calls `super`, i.e. the
# real Async delivery still runs. Session B's page is a genuine second
# WebSocket subscriber on the same Action Cable pubsub. `wait:` on every
# assertion below accounts for that delivery being asynchronous (a real
# round trip through the Async adapter's dispatch), not for flakiness in the
# test itself.
#
# A room with ZERO notes renders NEITHER the notes `<ul>` NOR its
# `turbo_stream_from` subscription at all (notes/_list.html.erb only renders
# the section when `own_roots.any? || own_can_create`) — session B, a plain
# viewer with no create permission, would never even subscribe if the room
# started with no notes. `seed_note` exists purely to make the section (and
# its subscription) present for session B before session A does anything.
#
# The request-level `have_broadcasted_to(notable)` coverage the brief's
# fallback describes (prepend into the roots list, prepend into a parent's
# replies, remove on destroy) already exists exhaustively at
# spec/models/note_spec.rb's "Broadcastable" describe block — not duplicated
# here.
RSpec.describe "Notes live updates", type: :system do
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  let!(:workspace) { create(:workspace, slug: "notes-live-updates-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  let!(:building) { create(:building, workspace: workspace) }
  let!(:unit) { create(:unit, workspace: workspace) }
  let!(:room) do
    create(:room, building: building, workspace: workspace, unit: unit,
           room_number: "1200", facility_code: "MLB1200")
  end

  # An editor on the room's own unit — NotePolicy#writable? admits an admin,
  # or (Room notes only) the room's assigned-unit editor while it's visible.
  let(:editor) do
    user = create(:user)
    create(:editor_assignment, user: user, unit: unit)
    user
  end

  # A plain member with no create permission — session B. Auto-joins the
  # shared workspace as a viewer (MiClassrooms' shared_join_role), same as
  # `editor` before its EditorAssignment.
  let(:observer) { create(:user) }

  # See the file header: keeps the notes section (and its turbo_stream_from
  # subscription) rendering for `observer` before session A creates anything.
  let!(:seed_note) do
    create(:note, notable: room, workspace: workspace, author: editor, body: "Existing note")
  end

  # Fills Lexxy's contenteditable region directly. Lexxy (app/views/notes/
  # _form.html.erb's `form.rich_text_area :body`) renders a `<lexxy-editor>`
  # custom element whose actual editable surface is a NESTED
  # `[contenteditable]` div (id "#{field_id}-content") — the `<label for=...>`
  # points at the OUTER custom element, not that inner div, so Capybara's
  # built-in label-driven `fill_in` can't resolve it (verified empirically:
  # `fill_in "Note", with: ...` raises ElementNotFound here). `.set` on the
  # contenteditable node itself (Capybara's native contenteditable support)
  # is the one interaction that reliably works under the Playwright driver.
  def fill_in_lexxy(within_selector, text)
    within(within_selector) { find(".lexxy-editor__content").set(text) }
  end

  it "room page with the note create form open is axe-clean at AAA (both themes)" do
    sign_in_via_form(editor)
    visit room_path(room)

    expect(page).to have_css("##{ActionView::RecordIdentifier.dom_id(room, :new_note)}")
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations with the note create form open:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end

  it "live-prepends an alert note and a reply, then live-removes the reply, into a SECOND session watching the same page" do
    using_session(:observer_session) do
      sign_in_via_form(observer)
      visit room_path(room)
      expect(page).to have_css("##{ActionView::RecordIdentifier.dom_id(seed_note)}")
    end

    using_session(:editor_session) do
      sign_in_via_form(editor)
      visit room_path(room)

      new_note_container = "##{ActionView::RecordIdentifier.dom_id(room, :new_note)}"
      fill_in_lexxy(new_note_container, "Projector bulb needs replacement")
      within(new_note_container) do
        check I18n.t("notes.form.alert_label")
        click_button I18n.t("notes.form.create_submit")
      end

      # Form-and-toast only (NotesController#respond_with_result) — the
      # actor's OWN page never gets the note in the HTTP response, only via
      # the same broadcast session B is about to receive.
      expect(page).to have_content(I18n.t("notes.toasts.create"))
    end

    note = Note.where(notable: room).where.not(id: seed_note.id).sole
    expect(note.alert).to be(true)
    note_selector = "##{ActionView::RecordIdentifier.dom_id(note)}"

    using_session(:observer_session) do
      expect(page).to have_css(note_selector, wait: 5)
      within(note_selector) do
        expect(page).to have_css("[role='alert']")
        expect(page).to have_content(note.body.to_plain_text)
      end
    end

    using_session(:editor_session) do
      within(note_selector) { find("summary", text: I18n.t("notes.actions.reply")).click }
      reply_container = "##{ActionView::RecordIdentifier.dom_id(note, :new_reply)}"
      fill_in_lexxy(reply_container, "On it, ordering a replacement bulb")
      within(reply_container) { click_button I18n.t("notes.form.reply_submit") }

      expect(page).to have_content(I18n.t("notes.toasts.create"))
    end

    reply = note.replies.sole
    replies_list = "##{ActionView::RecordIdentifier.dom_id(note)}_replies"
    reply_selector = "##{ActionView::RecordIdentifier.dom_id(reply)}"

    using_session(:observer_session) do
      expect(page).to have_css("#{replies_list} #{reply_selector}", wait: 5)
    end

    using_session(:editor_session) do
      # Destroy the reply (not the root) — a reply has no nested
      # replies/edit affordances of its own, so its delete button stays
      # unambiguous; the root note's own delete button would otherwise be
      # ambiguous with its reply's once both are on the page.
      within(reply_selector) do
        accept_confirm(I18n.t("notes.actions.delete_confirm")) do
          click_button I18n.t("notes.actions.delete")
        end
      end

      expect(page).to have_content(I18n.t("notes.toasts.destroy"))
    end

    expect { reply.reload }.to raise_error(ActiveRecord::RecordNotFound)

    using_session(:observer_session) do
      expect(page).to have_no_css(reply_selector, wait: 5)
    end
  end
end
