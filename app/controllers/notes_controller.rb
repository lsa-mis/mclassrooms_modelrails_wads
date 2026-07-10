# MiClassrooms Phase 5 Task 7 (Brief §14.1, D15): notes/alerts CRUD. A
# product-level resource (config/routes/app.rb), not nested under
# rooms/buildings — a note's own notable_type/notable_id (hidden fields on
# notes/_form.html.erb) says which record it's on; NotePolicy authorizes off
# that `record.notable`, not a parent resource in the URL.
#
# Every mutation routes through Curation::Apply (Note does NOT include
# Trackable — see app/models/note.rb) so the audit trail and the write
# commit or roll back together. Authorization is NotePolicy#writable?: an
# admin, or (Room notes only) the room's assigned-unit editor — building
# notes stay admin-only (interpretation 2).
#
# The turbo_stream response is deliberately form-and-toast ONLY. Note's own
# Broadcastable wiring (app/models/note.rb#broadcast_changes) prepends,
# replaces, or removes the note for every subscribed page — the acting
# user's own page included, since notes/_list.html.erb's turbo_stream_from
# subscribes before any submission is possible. Rendering the note here too
# would double-insert it for the actor.
class NotesController < ApplicationController
  include DirectoryScoped
  include ActionView::RecordIdentifier # dom_id, for the reset-target ids below

  ALLOWED_NOTABLE_TYPES = %w[Room Building].freeze

  before_action :set_note, only: [ :update, :destroy ]

  def create
    notable = resolve_notable
    parent = resolve_parent(notable)
    @note = Note.new(notable: notable, author: Current.user, parent: parent, workspace: Current.workspace)
    authorize @note

    result = Curation::Apply.call(record: @note, actor: Current.user, action: "note.created", attributes: note_params)
    respond_with_result(result, reset_target: reset_target_for(notable, parent))
  end

  def update
    authorize @note
    result = Curation::Apply.call(record: @note, actor: Current.user, action: "note.updated", attributes: note_params)
    respond_with_result(result)
  end

  def destroy
    authorize @note
    result = Curation::Apply.call(record: @note, actor: Current.user, action: "note.destroyed") { |note| note.destroy! }
    respond_with_result(result)
  end

  private

  def set_note
    # for_current_workspace (CLAUDE.md deviation #1): no unscoped Note.find,
    # mirrors RoomsController#set_room.
    @note = Note.for_current_workspace.find(params[:id])
  end

  # Allow-list, then resolve through the request's workspace rather than a
  # bare `constantize.find` — mirrors RoomsController#set_room's
  # for_current_workspace guard, so a crafted notable_id from outside the
  # current workspace can never be reached.
  def resolve_notable
    type = params.dig(:note, :notable_type)
    raise ActiveRecord::RecordNotFound unless ALLOWED_NOTABLE_TYPES.include?(type)

    type.constantize.for_current_workspace.find(params.dig(:note, :notable_id))
  end

  # Scoped through the notable's OWN association (not a global Note.find) —
  # a submitted parent_id can only ever name a note already on this exact
  # notable, never a note anywhere else. Deliberately NOT `.roots`-scoped:
  # a reply-to-a-reply must still reach Note#parent_must_be_root (a model
  # validation, surfaced as the documented 422), not be swallowed here as a
  # 404 before the model ever sees it.
  def resolve_parent(notable)
    parent_id = params.dig(:note, :parent_id)
    return nil if parent_id.blank?

    notable.notes.find(parent_id)
  end

  # :notable_type/:notable_id/:parent_id are resolved above, never mass-
  # assigned — only :body/:alert flow through Curation::Apply's attributes:,
  # for BOTH create and update. That also means an edit can never reparent
  # or re-notable an existing note (update reuses this same method).
  def note_params
    params.expect(note: [ :body, :alert ])
  end

  # Which "reset this form" turbo-stream target a successful create should
  # target: the reply form nested under the parent when replying, otherwise
  # the notable's own top-level create form — matches the ids
  # notes/_list.html.erb and notes/_note.html.erb render.
  def reset_target_for(notable, parent)
    parent ? dom_id(parent, :new_reply) : dom_id(notable, :new_note)
  end

  def respond_with_result(result, reset_target: nil)
    if result.success?
      respond_to do |format|
        format.turbo_stream { render turbo_stream: success_streams(reset_target) }
        format.html { redirect_to request.referer || root_path, notice: t("notes.toasts.#{action_name}") }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: error_toast(result.errors.to_sentence), status: :unprocessable_content
        end
        format.html { redirect_to request.referer || root_path, alert: result.errors.to_sentence }
      end
    end
  end

  # Form-and-toast only — see the class comment: inserting/replacing/
  # removing the note itself is the model broadcast's job, never rendered
  # here. Re-renders a FRESH blank create/reply form into the exact
  # container the actor's form came from, so their just-submitted form is
  # visibly reset rather than left showing stale (already-saved) input.
  # `reset_target` names the spacing <div> the view renders around
  # notes/_form (see that partial's header comment) — the form itself no
  # longer carries that id, so this must be `update` (swap the div's inner
  # content) rather than `replace` (which would consume the div itself and
  # drop its mt-3/mt-2 spacing on the very first reset).
  def success_streams(reset_target)
    streams = [ success_toast(t("notes.toasts.#{action_name}")) ]
    return streams unless reset_target

    parent = @note.parent
    form_locals = parent ? { notable: parent.notable, parent: parent } : { notable: @note.notable, parent: nil }
    streams.unshift(turbo_stream.update(reset_target, partial: "notes/form", locals: form_locals))
  end
end
