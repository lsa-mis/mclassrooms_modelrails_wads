class Membership < ApplicationRecord
  # How a membership arrived, and who acted: the non-persisted markers that feed
  # the audit row and the notification actor, and the rules that keep them apart.
  # See /docs/developer/notifications (The actor rule) and /docs/developer/membership-lifecycle.
  module Provenance
    extend ActiveSupport::Concern

    SELF_JOIN_GRADES = [ nil, false, true, :onboarding ].freeze

    CONFLICTING_PROVENANCE_MESSAGE =
      "granted_by and self_join are mutually exclusive: a self-join has no granter"

    # Non-persisted grant provenance for the creation audit entry (G): set by
    # Workspace#admit when an invitation acceptance created this membership.
    attr_accessor :granted_by

    # Non-persisted self-join marker. Grades, and why it is kept apart from granted_by:
    # /docs/developer/notifications (The actor rule).
    attr_accessor :self_join

    # Non-persisted removal actor (#933), an argument to #deactivate! — the model never reads Current.
    # See /docs/developer/notifications (The actor rule).
    attr_accessor :removed_by

    included do
      # Model invariant, not only the entry-point guard: direct creates (User#join_shared_workspace) never
      # see .reject_conflicting_provenance!. See /docs/developer/membership-lifecycle.
      validate :provenance_markers_are_coherent
    end

    class_methods do
      # Mutually exclusive, and refused rather than documented. See /docs/developer/notifications (The actor rule).
      def reject_conflicting_provenance!(granted_by:, self_join:)
        return unless granted_by && self_join
        raise ArgumentError, CONFLICTING_PROVENANCE_MESSAGE
      end
    end

    private

    def provenance_markers_are_coherent
      errors.add(:base, CONFLICTING_PROVENANCE_MESSAGE) if granted_by && self_join
      return if SELF_JOIN_GRADES.include?(self_join)

      errors.add(:base,
        "self_join must be one of #{SELF_JOIN_GRADES.map(&:inspect).join(', ')}, " \
        "got #{self_join.inspect}")
    end

    # Inclusion, not `!= :onboarding`: an unvalidated new grade must not read as "chosen" and mail someone.
    def chosen_self_join?
      self_join == true
    end
  end
end
