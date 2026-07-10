# frozen_string_literal: true

# MiClassrooms Phase 5 Task 8 (Brief §14.1): admin CRUD for the three fixed
# announcement slots (home_page/find_a_room_page/about_page) — the last admin
# console in phase 5. AnnouncementPolicy denies every action to a non-admin
# unconditionally (grant.admin? only, no editor carve-out — see the policy's
# own header comment), so `authorize` is unconditional here on every action,
# same shape as Admin::BulkUploadsController.
#
# Every mutation flows through Curation::Apply (Announcement is Trackable-
# free — spec/lib/curation/apply_spec.rb's "sole audit writer" assertion
# covers it) so the record write and its ActivityLog commit or roll back
# together, in ONE transaction (spec D13).
module Admin
  class AnnouncementsController < ApplicationController
    include DirectoryScoped

    before_action :set_announcement, only: [ :edit, :update, :destroy ]

    # Lists all THREE fixed slots (Announcement.slots.keys), not just the
    # rows that happen to be persisted — an empty slot is a first-class list
    # item here (a "create" affordance), not simply absent, so the view
    # always renders exactly three rows regardless of how many are filled.
    def index
      authorize Announcement
      @announcements_by_slot = Announcement.slots.keys.index_with { |slot| Announcement.for(slot) }
    end

    # Offers ONLY unfilled slots (Brief §14.1) — a slot that already has an
    # announcement has no "create" affordance in the picker; the admin edits
    # the existing row from #index instead. Redirects back to #index with an
    # alert rather than rendering a picker with zero options when every slot
    # is already filled (the three-slot cap is intentional, not a bug to
    # silently tolerate).
    def new
      authorize Announcement
      @unfilled_slots = unfilled_slots
      return redirect_to(admin_announcements_path, alert: t(".no_unfilled_slots")) if @unfilled_slots.empty?

      @announcement = Announcement.new(slot: params[:slot].presence_in(@unfilled_slots) || @unfilled_slots.first)
    end

    # `workspace: Current.workspace` assigned explicitly — Announcement is
    # Tenanted (`belongs_to :workspace`, required), and DirectoryScoped only
    # sets Current.workspace, it doesn't default a new record's association.
    # Mirrors NotesController#create's identical `Note.new(...,
    # workspace: Current.workspace)`.
    def create
      authorize Announcement
      @announcement = Announcement.new(workspace: Current.workspace)
      result = Curation::Apply.call(record: @announcement, actor: Current.user,
                                    action: "announcement.created", attributes: announcement_params)

      if result.success?
        redirect_to admin_announcements_path, notice: t(".success")
      else
        # A duplicate-slot submission (Announcement's global uniqueness
        # validation, app/models/announcement.rb) lands here as an ordinary
        # Result.failure — re-render :new with the model's own error
        # attached and the picker recomputed from the CURRENT persisted
        # state (the rejected slot was never actually written, so it stays
        # correctly excluded from `unfilled_slots` either way).
        @announcement = result.payload[:record] || @announcement
        @unfilled_slots = unfilled_slots
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @announcement
    end

    # :slot is deliberately not in announcement_params for this action (see
    # that method below) — a slot is fixed at creation; editing only ever
    # changes body.
    def update
      authorize @announcement
      result = Curation::Apply.call(record: @announcement, actor: Current.user,
                                    action: "announcement.updated", attributes: announcement_params)

      if result.success?
        redirect_to admin_announcements_path, notice: t(".success")
      else
        @announcement = result.payload[:record] || @announcement
        render :edit, status: :unprocessable_entity
      end
    end

    # Block form (Curation::Apply's second call shape) — a destroy is not
    # plain attribute assignment, so the record + its audit row are still
    # written in the SAME transaction via the block.
    def destroy
      authorize @announcement
      result = Curation::Apply.call(record: @announcement, actor: Current.user,
                                    action: "announcement.destroyed") { |announcement| announcement.destroy! }

      if result.success?
        redirect_to admin_announcements_path, notice: t(".success")
      else
        redirect_to admin_announcements_path, alert: result.errors.to_sentence
      end
    end

    private

    # for_current_workspace (CLAUDE.md deviation #1): no unscoped
    # Announcement.find, mirrors RoomsController#set_room/
    # BuildingsController#set_building/NotesController#set_note — even
    # though Announcement.for (the app's OTHER lookup, used by
    # PagesController/RoomsController for rendering) is a deliberate GLOBAL
    # find_by (see app/models/announcement.rb's own comment), resolving a
    # single row by id for a mutation still goes through the request's own
    # workspace like every other admin mutation surface in this app.
    def set_announcement
      @announcement = Announcement.for_current_workspace.find(params[:id])
    end

    def unfilled_slots
      Announcement.slots.keys - Announcement.pluck(:slot)
    end

    # :slot is only ever permitted on #create — once a row exists its slot
    # is fixed, and #update's form never renders a control for it (see
    # admin/announcements/_form.html.erb), so no crafted request can smuggle
    # a slot change past this either.
    def announcement_params
      permitted = action_name == "create" ? [ :slot, :body ] : [ :body ]
      params.expect(announcement: permitted)
    end
  end
end
