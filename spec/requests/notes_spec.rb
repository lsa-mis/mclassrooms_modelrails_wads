require "rails_helper"

# MiClassrooms Phase 5 Task 7 (Brief §14.1, D15): NotesController — every
# mutation must write the matching note.created/note.updated/note.destroyed
# ActivityLog via Curation::Apply (destroy via the block form, cascading to
# replies), authorize through NotePolicy (admin, or the room's
# assigned-unit editor; buildings stay admin-only — interpretation 2), and
# respond turbo_stream with a reset form + toast ONLY — never the note
# itself, since Note's own Broadcastable wiring is what inserts/replaces/
# removes it for every subscriber, actor included. Mirrors
# spec/requests/rooms_update_spec.rb's tenancy setup (shared-posture stub +
# workspace-scoped fixtures + sign_in) and its membership_with/editor_for
# helpers.
RSpec.describe "Notes", type: :request do
  let(:workspace) { create(:workspace, slug: "notes-spec-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  # Same reuse-and-re-role pattern as rooms_update_spec.rb: `create(:user)`
  # auto-joins `workspace` via `User#onboard_workspace` under the :shared
  # posture stubbed above.
  def membership_with(slug)
    user = create(:user)
    membership = Membership.find_by!(user: user, workspace: workspace)
    membership.update!(role: Role.system_default!(slug))
    user
  end

  # An editor: a plain viewer-role membership PLUS an EditorAssignment on a
  # specific unit — RoleResolver#editor?/#can_edit_room? derive entirely
  # from the EditorAssignment table, not the Membership role.
  def editor_for(unit)
    user = membership_with("viewer")
    create(:editor_assignment, user: user, unit: unit)
    user
  end

  def note_params_for(notable, **overrides)
    { notable_type: notable.class.name, notable_id: notable.id, body: "A note body", alert: "0" }.merge(overrides)
  end

  let(:building) { create(:building, workspace: workspace) }
  let(:unit) { create(:unit, workspace: workspace) }
  let(:other_unit) { create(:unit, workspace: workspace) }
  let!(:room_in_unit) { create(:room, building: building, workspace: workspace, unit: unit) }
  let!(:room_other_unit) { create(:room, building: building, workspace: workspace, unit: other_unit) }

  describe "POST /notes" do
    context "as an admin" do
      let(:admin) { membership_with("admin") }
      before { sign_in(admin) }

      it "creates a note on a room, audits note.created via Curation::Apply, and resets the form without inserting the note" do
        expect {
          post notes_path, params: { note: note_params_for(room_in_unit) }, as: :turbo_stream
        }.to change(ActivityLog, :count).by(1).and change(Note, :count).by(1)

        expect(response).to have_http_status(:ok)

        log = ActivityLog.last
        expect(log.action).to eq("note.created")
        expect(log.trackable).to eq(Note.last)
        expect(log.actor).to eq(admin)

        # No double-insert: the turbo_stream response resets the create form
        # (present) but never renders the just-created note's own body.
        expect(response.body).to include("form")
        expect(response.body).not_to include("A note body")
      end

      it "creates a note on a building (admin-only, interpretation 2)" do
        expect {
          post notes_path, params: { note: note_params_for(building) }, as: :turbo_stream
        }.to change(ActivityLog, :count).by(1)

        expect(ActivityLog.last.action).to eq("note.created")
        expect(Note.last.notable).to eq(building)
      end

      it "creates a reply to a root note" do
        root = create(:note, notable: room_in_unit, workspace: workspace)

        expect {
          post notes_path, params: { note: note_params_for(room_in_unit, parent_id: root.id) }, as: :turbo_stream
        }.to change(ActivityLog, :count).by(1)

        expect(ActivityLog.last.action).to eq("note.created")
        expect(Note.last.parent).to eq(root)
      end

      it "rejects a reply-to-a-reply with 422 (Note#parent_must_be_root)" do
        root = create(:note, notable: room_in_unit, workspace: workspace)
        reply = create(:note, notable: room_in_unit, workspace: workspace, parent: root)

        expect {
          post notes_path, params: { note: note_params_for(room_in_unit, parent_id: reply.id) }, as: :turbo_stream
        }.not_to change(ActivityLog, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "as the room's assigned-unit editor" do
      let(:editor) { editor_for(unit) }
      before { sign_in(editor) }

      it "creates a note on their own unit's room" do
        expect {
          post notes_path, params: { note: note_params_for(room_in_unit) }, as: :turbo_stream
        }.to change(ActivityLog, :count).by(1)

        expect(ActivityLog.last.action).to eq("note.created")
        expect(ActivityLog.last.actor).to eq(editor)
      end

      it "is denied creating a note on a building" do
        expect {
          post notes_path, params: { note: note_params_for(building) }
        }.not_to change(ActivityLog, :count)

        expect(response).to redirect_to(find_a_room_path)
      end

      it "is denied creating a note on another unit's room" do
        expect {
          post notes_path, params: { note: note_params_for(room_other_unit) }
        }.not_to change(ActivityLog, :count)

        expect(response).to redirect_to(find_a_room_path)
      end
    end

    context "as a viewer" do
      let(:viewer) { membership_with("viewer") }
      before { sign_in(viewer) }

      it "is denied creating a note" do
        expect {
          post notes_path, params: { note: note_params_for(room_in_unit) }
        }.not_to change(ActivityLog, :count)

        expect(response).to redirect_to(find_a_room_path)
      end
    end
  end

  # Finding 1 regression (Phase 5 Task 7 review): the only a11y/rendering
  # sweep that visits a room's notes section (spec/system/rooms/show_spec.rb)
  # runs as a plain (non-authoring) user, so it never renders the create-note
  # form and never caught the duplicate DOM id below. notes/_list.html.erb
  # wraps "notes/form" in a `<div id="#{dom_id(notable, :new_note)}">`; the
  # form partial used to ALSO carry that same id on its own `<form>` tag
  # (invalid HTML — two elements sharing one id), and NotesController's reset
  # stream used to `replace` that id, which a browser's `getElementById`
  # resolves to the FIRST (outer) element — dropping the div's `mt-3`
  # spacing after the first successful submit. Both are fixed: the id lives
  # on the div only now, and the reset stream `update`s the div's inner
  # content instead of replacing the div itself.
  describe "GET /rooms/:id (inline authoring form ids)" do
    let(:editor) { editor_for(unit) }
    before { sign_in(editor) }

    it "renders the create-note form's DOM id exactly once" do
      get room_path(room_in_unit)

      expect(response).to have_http_status(:ok)

      new_note_id = ActionView::RecordIdentifier.dom_id(room_in_unit, :new_note)
      expect(response.body.scan(%r{id="#{new_note_id}"}).size).to eq(1)
    end

    it "resets the create form via turbo_stream.update (not .replace), so the wrapper survives for a second submit" do
      new_note_id = ActionView::RecordIdentifier.dom_id(room_in_unit, :new_note)

      post notes_path, params: { note: note_params_for(room_in_unit) }, as: :turbo_stream
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(action="update" target="#{new_note_id}"))
      expect(response.body).not_to include(%(action="replace" target="#{new_note_id}"))

      # A second submit against the exact same target must still succeed:
      # if the first reset had `replace`d the wrapper div (consuming its
      # id), a real browser's next reset stream would have nothing left to
      # target. Two-for-two proves the wrapper (and its id) survives.
      expect {
        post notes_path, params: { note: note_params_for(room_in_unit) }, as: :turbo_stream
      }.to change(Note, :count).by(1)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(action="update" target="#{new_note_id}"))
    end

    # Whole-branch review I-1 (WCAG 2.2 AAA): notes/_form.html.erb renders
    # via `form_with model: record`, which derives its field ids from
    # `record.model_name.param_key` — "note" for a Note whether new OR
    # persisted. With one existing root note, an authoring editor's room
    # page renders THREE note forms (top create, that note's inline edit,
    # that note's reply) that, pre-fix, all emit the SAME body-field id
    # (`note_body`), so every `form.label :body` resolves to the FIRST
    # `#note_body` in document order (WCAG 1.3.1/3.3.2/4.1.2 failures at
    # AAA). This spec fails pre-fix (all 3 ids collapse to 1 unique value)
    # and passes once each context's field id is made unique.
    it "gives the create, edit, and reply forms distinct Lexxy body-field ids (I-1)" do
      create(:note, notable: room_in_unit, workspace: workspace)

      get room_path(room_in_unit)

      expect(response).to have_http_status(:ok)

      body_field_ids = response.body.scan(/id="([^"]*note_body)"/).flatten
      # Sanity: the create form + the existing note's edit form + its reply
      # form all render for an authoring editor with one root note present.
      expect(body_field_ids.size).to eq(3)
      expect(body_field_ids.uniq.size).to eq(body_field_ids.size)
    end
  end

  describe "PATCH /notes/:id" do
    let!(:note) { create(:note, notable: room_in_unit, workspace: workspace) }

    context "as an admin" do
      let(:admin) { membership_with("admin") }
      before { sign_in(admin) }

      it "updates the note, audits note.updated, and responds with a toast only (no note markup)" do
        expect {
          patch note_path(note), params: { note: { body: "Updated by admin" } }, as: :turbo_stream
        }.to change(ActivityLog, :count).by(1)

        log = ActivityLog.last
        expect(log.action).to eq("note.updated")
        expect(log.trackable).to eq(note)
        expect(note.reload.body.to_plain_text).to eq("Updated by admin")

        # No double-insert: the update broadcast (not this response) replaces
        # the note in place — the HTTP response body carries no note markup.
        expect(response.body).not_to include("Updated by admin")
      end
    end

    context "as the room's assigned-unit editor" do
      let(:editor) { editor_for(unit) }
      before { sign_in(editor) }

      it "updates the note" do
        expect {
          patch note_path(note), params: { note: { body: "Updated by editor" } }, as: :turbo_stream
        }.to change(ActivityLog, :count).by(1)

        expect(ActivityLog.last.action).to eq("note.updated")
        expect(note.reload.body.to_plain_text).to eq("Updated by editor")
      end
    end

    context "as the other unit's editor" do
      let(:other_editor) { editor_for(other_unit) }
      before { sign_in(other_editor) }

      it "is denied updating the note" do
        expect {
          patch note_path(note), params: { note: { body: "Hijacked" } }
        }.not_to change(ActivityLog, :count)

        expect(note.reload.body.to_plain_text).not_to eq("Hijacked")
        expect(response).to redirect_to(find_a_room_path)
      end
    end

    context "as a viewer" do
      let(:viewer) { membership_with("viewer") }
      before { sign_in(viewer) }

      it "is denied updating the note" do
        expect {
          patch note_path(note), params: { note: { body: "Hijacked" } }
        }.not_to change(ActivityLog, :count)

        expect(response).to redirect_to(find_a_room_path)
      end
    end
  end

  describe "DELETE /notes/:id" do
    let!(:note) { create(:note, notable: room_in_unit, workspace: workspace) }

    context "as an admin" do
      let(:admin) { membership_with("admin") }
      before { sign_in(admin) }

      it "destroys the note via the block form, cascading to its replies, with exactly one ActivityLog" do
        reply = create(:note, notable: room_in_unit, workspace: workspace, parent: note)

        expect {
          delete note_path(note), as: :turbo_stream
        }.to change(ActivityLog, :count).by(1).and change(Note, :count).by(-2)

        log = ActivityLog.last
        expect(log.action).to eq("note.destroyed")
        expect(log.before_after["after"]).to be_nil
        expect { reply.reload }.to raise_error(ActiveRecord::RecordNotFound)

        expect(response.body).not_to include(note.body.to_plain_text)
      end
    end

    context "as the room's assigned-unit editor" do
      let(:editor) { editor_for(unit) }
      before { sign_in(editor) }

      it "destroys the note" do
        expect {
          delete note_path(note), as: :turbo_stream
        }.to change(ActivityLog, :count).by(1).and change(Note, :count).by(-1)

        expect(ActivityLog.last.action).to eq("note.destroyed")
      end
    end

    context "as the other unit's editor" do
      let(:other_editor) { editor_for(other_unit) }
      before { sign_in(other_editor) }

      it "is denied destroying the note" do
        expect {
          delete note_path(note)
        }.not_to change(Note, :count)

        expect(response).to redirect_to(find_a_room_path)
      end
    end

    context "as a viewer" do
      let(:viewer) { membership_with("viewer") }
      before { sign_in(viewer) }

      it "is denied destroying the note" do
        expect {
          delete note_path(note)
        }.not_to change(Note, :count)

        expect(response).to redirect_to(find_a_room_path)
      end
    end
  end
end
