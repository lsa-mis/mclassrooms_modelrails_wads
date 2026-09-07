# frozen_string_literal: true

module RuboCop
  module Cop
    module ModelRails
      # `Current` is request state. A model reads it in two places only, both
      # excluded in .rubocop.yml with their reasons: Trackable, the audit
      # concern, where a callback cannot take an argument and a nil actor is
      # a true answer; and Tenanted's opt-in for_current_workspace scope.
      # Every domain verb takes its actor as a parameter, and a record's
      # tenant is its own association. See /docs/developer/architecture
      # (Actors are parameters).
      #
      #   # bad
      #   def demote!
      #     audit(actor: Current.user)
      #
      #   # good
      #   def deactivate!(removed_by:)
      class NoAmbientCurrentInModels < Base
        MSG = "`Current` is request state; a model reads it only inside the audit concern (Trackable) and the " \
              "opt-in for_current_workspace scope. Fix: take the actor as a parameter (`deactivate!(removed_by:)`) " \
              "and the tenant from the record's own association. Pattern: actors are parameters. " \
              "Read: /docs/developer/architecture (Actors are parameters)."

        def on_send(node)
          receiver = node.receiver
          return unless receiver&.const_type? && receiver.short_name == :Current
          return unless receiver.namespace.nil? || receiver.namespace.cbase_type?

          add_offense(node)
        end
      end
    end
  end
end
