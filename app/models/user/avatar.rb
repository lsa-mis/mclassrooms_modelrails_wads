class User < ApplicationRecord
  # A user's picture: an upload, their initials, or Gravatar when one exists.
  module Avatar
    extend ActiveSupport::Concern

    included do
      has_one_attached :avatar
      has_one_attached :avatar_original

      after_create :check_gravatar_later
      after_update_commit :check_gravatar_later, if: :saved_change_to_email_address?

      validates :avatar_source, inclusion: { in: %w[upload gravatar initials] }
      # ApplicationRecord's constant: lexical lookup from inside this module sees User's own
      # constants but not User's ancestors'.
      validates :avatar,
        content_type: ApplicationRecord::IMAGE_CONTENT_TYPES,
        size: { less_than: 5.megabytes }
      validates :avatar_original,
        content_type: ApplicationRecord::IMAGE_CONTENT_TYPES,
        size: { less_than: 10.megabytes }
      validates :primary_color, inclusion: { in: 0..360 }, allow_nil: true
    end

    def gravatar_url(size: 128)
      return nil if email_address.blank?

      hash = Digest::SHA256.hexdigest(EmailNormalizer.normalize(email_address))
      "https://www.gravatar.com/avatar/#{hash}?s=#{size}&d=404"
    end

    def available_avatar_sources
      sources = %w[upload initials]
      sources << "gravatar" if has_gravatar?
      sources
    end

    private

    def check_gravatar_later
      CheckGravatarJob.perform_later(self)
    end
  end
end
