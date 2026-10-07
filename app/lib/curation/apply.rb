# frozen_string_literal: true

module Curation
  # Transactional curation audit (spec D13, Brief §14.1): applies a change
  # AND writes its ActivityLog row in ONE transaction — either both commit
  # or both roll back. This is the compliance-grade escape hatch anticipated
  # by Trackable's best-effort header (template deviation #4). Curation
  # models must NOT include Trackable; Apply is their sole audit writer.
  #
  #   Curation::Apply.call(record:, actor:, action:, attributes: {...})   # assign + save!
  #   Curation::Apply.call(record:, actor:, action:) { |r| r.destroy! }   # block form
  #
  # The optional block covers mutations that are not plain attribute
  # assignment (destroy!, attachment purge/attach); it runs inside the same
  # transaction. Attachment operations produce an empty diff — the `action`
  # string carries the meaning ("room.photo_attached" etc.).
  class Apply
    IGNORED_DIFF_KEYS = %w[updated_at created_at].freeze

    # workspace: is passed explicitly where no request sets Current.workspace (the operations area).
    def self.call(record:, actor:, action:, attributes: {}, workspace: Current.workspace, &block)
      new(record:, actor:, action:, attributes:, workspace:, block:).call
    end

    def initialize(record:, actor:, action:, attributes:, workspace:, block:)
      @record, @actor, @action, @attributes, @workspace, @block = record, actor, action, attributes, workspace, block
    end

    def call
      @record.assign_attributes(@attributes) if @attributes.present?
      diff = @record.changes.except(*IGNORED_DIFF_KEYS)
      activity_log = nil

      ActiveRecord::Base.transaction do
        @block ? @block.call(@record) : @record.save!
        activity_log = ActivityLog.create!(
          actor: @actor, action: @action, trackable: @record,
          workspace: @workspace, visibility: "admin",
          before_after: before_after_payload(diff)
        )
      end

      Result.success(record: @record, activity_log: activity_log)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => e
      Result.failure(*(e.record.errors.full_messages.presence || [ e.message ]), record: e.record)
    end

    private

    def before_after_payload(diff)
      if @record.destroyed?
        { "before" => @record.attributes.except(*IGNORED_DIFF_KEYS), "after" => nil }
      else
        { "before" => diff.transform_values(&:first), "after" => diff.transform_values(&:last) }
      end
    end
  end
end
