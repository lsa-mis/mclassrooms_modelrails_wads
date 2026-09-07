# frozen_string_literal: true

module RuboCop
  module Cop
    module ModelRails
      # A file under app/models/<model>/ reopens the model and nests its module
      # or class; the compact `module Model::Trait` form does not open the
      # model's lexical scope, so the trait cannot see the model's constants.
      # See /docs/developer/extending (Per-model traits).
      #
      #   # bad
      #   module Invitation::Suppression
      #   end
      #
      #   # good
      #   class Invitation < ApplicationRecord
      #     module Suppression
      #     end
      #   end
      class ModelConcernNamespace < Base
        MSG = "`%<name>s` is defined in compact form, so it cannot see the model's constants. " \
              "Fix: reopen the model and nest the %<keyword>s " \
              "(`class %<model>s < ApplicationRecord; %<keyword>s %<trait>s`). " \
              "Pattern: per-model traits. Read: /docs/developer/extending (Per-model traits)."

        def on_module(node)
          check(node)
        end

        def on_class(node)
          check(node)
        end

        private

        def check(node)
          identifier = node.identifier
          return unless identifier.namespace
          return if identifier.namespace.cbase_type?
          return if node.each_ancestor(:class, :module).any?

          add_offense(identifier, message: format(MSG,
            name: identifier.const_name,
            model: identifier.namespace.const_name,
            keyword: node.type,
            trait: identifier.short_name))
        end
      end
    end
  end
end
