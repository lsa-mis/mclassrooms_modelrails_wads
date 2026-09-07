# frozen_string_literal: true

module RuboCop
  module Cop
    module ModelRails
      # Every routed action is one of the seven REST actions. A public method
      # on a controller with any other name is either a resource that has not
      # been named yet (a verb) or a helper that is not private.
      # ApplicationController, which no route reaches and whose public methods
      # are helper_method exposures, is excluded in .rubocop.yml with the
      # reason. See /docs/developer/extending (Only the seven actions).
      #
      #   # bad
      #   def archive
      #
      #   # good
      #   resource :archival, only: [:create, :destroy]   # in routes
      #   def create
      class RestfulActions < Base
        MSG = "`%<name>s` is not one of the seven REST actions, so it is either a resource that has not been " \
              "named yet or a helper that is not private. Fix: a verb becomes create/destroy (or update) on a " \
              "nested resource (`resource :archival`); a helper moves below `private`. " \
              "Pattern: REST with no cited exceptions. Read: /docs/developer/extending (Only the seven actions)."

        ACTIONS = %i[index show new create edit update destroy].freeze
        VISIBILITY = %i[private protected public].freeze

        def on_class(node)
          visibility = :public
          body_statements(node).each do |child|
            if child.send_type? && VISIBILITY.include?(child.method_name) && child.arguments.empty?
              visibility = child.method_name
            elsif child.def_type? && visibility == :public && !ACTIONS.include?(child.method_name)
              add_offense(child.loc.keyword.join(child.loc.name), message: format(MSG, name: child.method_name))
            end
          end
        end

        private

        # A one-statement class body is that statement, not a begin node.
        def body_statements(node)
          body = node.body
          return [] unless body

          body.begin_type? ? body.children : [ body ]
        end
      end
    end
  end
end
