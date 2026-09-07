# frozen_string_literal: true

module RuboCop
  module Cop
    module ModelRails
      # A translation call carries no inline `default:`. The runtime gate
      # (raise_on_missing_translations) and the static gate (i18n-tasks) both
      # look through a default, so a missing key with one looks healthy
      # forever. See /docs/developer/i18n (No inline defaults).
      #
      #   # bad
      #   t("things.title", default: "Things")
      #   I18n.t("things.#{key}.name", default: key.to_s.humanize)
      #
      #   # good
      #   t("things.title")            # and the key in config/locales/en/
      #   I18n.t("things.#{key}.name") # and a spec proving every key has a value
      class NoI18nDefault < Base
        MSG = "A `default:` on a translation call silences both i18n gates for this key, so a missing key " \
              "looks healthy forever. Fix: put the text under the key in config/locales/en/ " \
              "(`bundle exec i18n-tasks add-missing` files it) and drop the default; a dynamic key gets a " \
              "spec proving every value has one. Pattern: keys, never fallbacks. " \
              "Read: /docs/developer/i18n (No inline defaults)."

        RESTRICT_ON_SEND = %i[t translate].freeze

        def on_send(node)
          return unless translation_call?(node)

          node.arguments.each do |argument|
            next unless argument.hash_type?

            argument.pairs.each do |pair|
              add_offense(pair) if pair.key.sym_type? && pair.key.value == :default
            end
          end
        end

        private

        # Bare `t`/`translate` (views, helpers, controllers, components) or `I18n.t`.
        def translation_call?(node)
          receiver = node.receiver
          receiver.nil? || (receiver.const_type? && receiver.const_name == "I18n")
        end
      end
    end
  end
end
