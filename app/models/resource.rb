class Resource < ApplicationRecord
  include Discardable
  include Trackable

  ALLOWED_RESOURCEABLE_TYPES = %w[Document].freeze

  belongs_to :project
  belongs_to :resourceable, polymorphic: true, dependent: :destroy
  belongs_to :created_by, class_name: "User"

  enum :status, { draft: "draft", published: "published" }, default: "draft"

  validates :title, presence: true
  validates :resourceable_type, inclusion: { in: ALLOWED_RESOURCEABLE_TYPES }
  validates :position, numericality: { greater_than_or_equal_to: 0 }

  scope :positioned, -> { order(position: :asc) }
  scope :published, -> { where(status: "published") }

  after_commit :broadcast_changes, on: [:create, :update]

  private

  def broadcast_changes
    broadcast_refresh_to project
  rescue => e
    Rails.logger.warn("Broadcast failed: #{e.message}")
  end
end
