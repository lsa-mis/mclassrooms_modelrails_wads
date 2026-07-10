class Note < ApplicationRecord
  include Tenanted
  include Broadcastable
  include ActionView::RecordIdentifier # dom_id, used by broadcast_changes below

  belongs_to :notable, polymorphic: true
  belongs_to :author, class_name: "User"
  belongs_to :parent, class_name: "Note", optional: true, inverse_of: :replies
  has_many :replies, class_name: "Note", foreign_key: :parent_id,
           dependent: :destroy, inverse_of: :parent
  has_rich_text :body

  NOTABLE_TYPES = %w[Room Building].freeze

  validates :notable_type, inclusion: { in: NOTABLE_TYPES }
  validates :body, presence: true
  validate :parent_must_be_root
  validate :notable_must_match_parent

  scope :alerts,      -> { where(alert: true) }
  scope :plain_notes, -> { where(alert: false) }
  scope :roots,       -> { where(parent_id: nil) }

  # Phase 5 Task 7 (D15): action-specific streams instead of Broadcastable's
  # default create/update-only refresh — see broadcast_changes below.
  def self.broadcast_events = [ :create, :update, :destroy ]

  private

  def broadcast_target = notable

  # D15 ("interactive, threaded, LIVE notes & alerts"): a broadcast failure
  # must never break the write — same rescue posture as Broadcastable's own
  # default, reimplemented here because the target/action differ per
  # lifecycle event instead of a single broadcast_refresh_to.
  #
  # Target strings are load-bearing — they must exactly match the DOM ids
  # notes/_list.html.erb and notes/_note.html.erb render:
  #   - a new ROOT note prepends into "#{dom_id(notable)}_notes"
  #   - a new REPLY prepends into "#{dom_id(parent)}_replies"
  #   - an update replaces, and a destroy removes, this note's own
  #     "#{dom_id(self)}" element (the same id for both a root and a reply).
  # A destroyed root's replies cascade-delete (dependent: :destroy above),
  # each firing its OWN after_destroy_commit — redundant "remove" broadcasts
  # for elements the root's own removal already took with it are harmless
  # (Turbo's remove is a no-op on a target that's already gone).
  def broadcast_changes
    if destroyed?
      broadcast_remove_to broadcast_target, target: dom_id(self)
    elsif previously_new_record?
      list = parent_id? ? "#{dom_id(parent)}_replies" : "#{dom_id(notable)}_notes"
      broadcast_prepend_to broadcast_target, target: list,
                           partial: "notes/note", locals: { note: self }
    else
      broadcast_replace_to broadcast_target, target: dom_id(self),
                           partial: "notes/note", locals: { note: self }
    end
  rescue StandardError => e
    Rails.logger.error("Broadcast failed for Note##{id}: #{e.class}: #{e.message}")
  end

  def parent_must_be_root
    errors.add(:parent_id, :nested_reply_not_allowed) if parent&.parent_id.present?
  end

  # A reply belongs to the same notable as the note it replies to — this is
  # what lets NotePolicy#writable? authorize a reply by reading its own
  # `notable` instead of walking up to the parent's.
  def notable_must_match_parent
    return unless parent
    return if notable_type == parent.notable_type && notable_id == parent.notable_id

    errors.add(:notable, :must_match_parent_notable)
  end
end
