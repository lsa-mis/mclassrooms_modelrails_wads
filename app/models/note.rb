class Note < ApplicationRecord
  include Tenanted
  include Broadcastable

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

  scope :alerts,      -> { where(alert: true) }
  scope :plain_notes, -> { where(alert: false) }
  scope :roots,       -> { where(parent_id: nil) }

  private

  def broadcast_target = notable

  def parent_must_be_root
    errors.add(:parent_id, :nested_reply_not_allowed) if parent&.parent_id.present?
  end
end
