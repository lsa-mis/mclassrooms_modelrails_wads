module Archivable
  extend ActiveSupport::Concern

  included do
    scope :not_archived, -> { where(archived_at: nil) }
    scope :archived,     -> { where.not(archived_at: nil) }
  end

  def archive!
    update!(archived_at: Time.current)
  end

  def unarchive!
    update!(archived_at: nil)
  end

  def archived?
    archived_at.present?
  end
end
