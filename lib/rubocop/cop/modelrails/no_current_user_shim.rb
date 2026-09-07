# frozen_string_literal: true

module RuboCop
  module Cop
    module ModelRails
      # The signed-in user is read through `Current.user`. `current_user` is
      # defined once, on ApplicationController, as the bridge Pundit and the
      # mounted engines call; that file is excluded in .rubocop.yml with the
      # reason. A second definition anywhere else is a shim. See
      # /docs/developer/architecture (Authorization).
      #
      #   # bad
      #   def current_user
      #     Current.user
      #   end
      #
      #   # good
      #   Current.user
      class NoCurrentUserShim < Base
        MSG = "`current_user` is defined once, on ApplicationController, as the bridge Pundit and the mounted " \
              "engines call; everything else reads `Current.user` (`Current.user!` where nil is a bug). " \
              "Fix: delete this definition and read Current.user. Pattern: one signed-in-user reader. " \
              "Read: /docs/developer/architecture (Authorization)."

        NAME = :current_user
        MINTERS = %i[alias_method delegate].freeze
        RESTRICT_ON_SEND = MINTERS

        def on_def(node)
          add_offense(node.loc.keyword.join(node.loc.name)) if node.method?(NAME)
        end
        alias on_defs on_def

        def on_send(node)
          return unless MINTERS.include?(node.method_name)
          return unless node.arguments.any? { |argument| argument.sym_type? && argument.value == NAME }

          add_offense(node)
        end

        def on_alias(node)
          add_offense(node) if node.new_identifier.value == NAME
        end
      end
    end
  end
end
