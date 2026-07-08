class Building < ApplicationRecord
  include Tenanted

  belongs_to :campus, optional: true
  belongs_to :hidden_by, class_name: "User", optional: true
  has_many :rooms, dependent: :destroy
  has_many :floors, dependent: :destroy
  has_many :notes, as: :notable, dependent: :destroy
  has_one_attached :photo

  validates :bldrecnbr, presence: true, uniqueness: true
  validates :name, presence: true
  validates :photo, content_type: [ :png, :jpeg, :webp ],
                    size: { less_than_or_equal_to: 10.megabytes }

  # D6 visibility split: in_feed sync-owned; hidden_at/hidden_by curation-owned.
  scope :listed,      -> { where(in_feed: true, hidden_at: nil) }
  scope :hidden,      -> { where.not(hidden_at: nil) }
  scope :not_in_feed, -> { where(in_feed: false) }

  def display_name = nickname.present? ? "#{name} (#{nickname})" : name

  def hidden? = hidden_at.present?
end
