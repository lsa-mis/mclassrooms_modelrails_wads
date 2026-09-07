# frozen_string_literal: true

module RuboCop
  module Cop
    module ModelRails
      # Tenant scoping is opt-in: `Tenanted` installs no `default_scope`, and
      # neither does anything else. A default scope acts at a distance on
      # every query, including the ones a job, the console, and an association
      # never meant. See /docs/developer/extending (Decide how it is tenant-scoped).
      #
      #   # bad
      #   default_scope { where(workspace_id: Current.workspace&.id) }
      #
      #   # good
      #   scope :for_current_workspace, -> { where(workspace: Current.workspace) }
      #   @workspace.milestones
      class NoDefaultScope < Base
        MSG = "`default_scope` scopes every query on this model from a distance, including the ones a job, " \
              "the console, and an association never meant. Fix: remove it; resolve tenant records through " \
              "the workspace association (`@workspace.%<association>s`) or the opt-in `for_current_workspace` " \
              "scope, and put ordering or filtering in a named scope. Pattern: opt-in tenant scoping. " \
              "Read: /docs/developer/extending (Decide how it is tenant-scoped)."

        RESTRICT_ON_SEND = %i[default_scope].freeze

        def on_send(node)
          return unless node.receiver.nil? || node.receiver.self_type?

          add_offense(node.loc.selector, message: format(MSG, association: association_name(node)))
        end

        private

        # The enclosing class's name as a collection, for the fix text; a
        # generic word when the call sits outside a class.
        def association_name(node)
          klass = node.each_ancestor(:class).first
          return "records" unless klass

          klass.identifier.short_name.to_s
               .gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
               .then { |name| "#{name}s" }
        end
      end
    end
  end
end
