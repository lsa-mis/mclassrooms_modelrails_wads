# frozen_string_literal: true

module RuboCop
  module Cop
    module ModelRails
      # A system spec waits for observable state, never for a clock. Two
      # shapes look like `sleep` and are not the banned one: the tick of a
      # bounded poll (`sleep 0.05 until ...`, or a `sleep` inside a `loop`,
      # `until`, `while`, or `times` block), and a named negative wait, which
      # gives a request time to NOT arrive and carries an inline comment
      # naming what it waits out. See /docs/developer/testing (Waiting in
      # system specs).
      #
      #   # bad
      #   click_button "Save"
      #   sleep 1
      #   expect(page).to have_text("Saved")
      #
      #   # good
      #   expect(page).to have_text("Saved")
      #   Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until settled? }
      #   sleep 0.3 # post-connect round-trip margin for a wrongful clobber
      class NoSleepInSystemSpecs < Base
        MSG = "`sleep` waits for a clock, not for the thing you mean, so under load it passes green with the " \
              "state you wanted still on its way. Fix: wait for observable state " \
              "(`expect(page).to have_css(...)`, or a bounded poll: " \
              "`Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until <condition> }`); " \
              "a wait that gives a request time to NOT arrive carries an inline comment naming what it waits out. " \
              "Pattern: observable-state waits. Read: /docs/developer/testing (Waiting in system specs)."

        RESTRICT_ON_SEND = %i[sleep].freeze
        POLL_METHODS = %i[loop times].freeze

        def on_send(node)
          return unless node.receiver.nil?
          return if poll_tick?(node)
          return if named_negative_wait?(node)

          add_offense(node)
        end

        private

        # The tick of a bounded poll: the body of an `until`/`while` (modifier
        # or block form), or inside a `loop`/`times` block.
        def poll_tick?(node)
          node.each_ancestor.any? do |ancestor|
            (ancestor.until_type? || ancestor.while_type?) ||
              (ancestor.block_type? && POLL_METHODS.include?(ancestor.send_node.method_name))
          end
        end

        # A comment on the sleep's own line is the reason the rule asks for.
        def named_negative_wait?(node)
          line = node.loc.line
          processed_source.comments.any? { |comment| comment.loc.line == line }
        end
      end
    end
  end
end
