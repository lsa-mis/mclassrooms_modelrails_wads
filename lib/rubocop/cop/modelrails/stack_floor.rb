# frozen_string_literal: true

module RuboCop
  module Cop
    module ModelRails
      # The stack has a floor: Rails 8.1+, Propshaft, import maps, Hotwire,
      # built-in authentication, Solid Queue/Cache/Cable. A Gemfile line that
      # brings in what the floor replaces, or pins rails below it, is an
      # offense. See /docs/developer/getting-started (The stack).
      #
      #   # bad
      #   gem "devise"
      #   gem "rails", "~> 7.2"
      #
      #   # good
      #   gem "rails", "~> 8.1.3"
      class StackFloor < Base
        MSG_GEM = "`%<gem>s` is below the stack floor: the app uses %<replacement>s. " \
                  "Fix: remove the gem and build on what the stack already has. " \
                  "Pattern: Rails 8.1+ floor. Read: /docs/developer/getting-started (The stack)."
        MSG_RAILS = "`rails` is pinned below the stack floor (`%<requirement>s`): the app is Rails 8.1 or newer. " \
                    "Fix: raise the requirement and run the upgrade. " \
                    "Pattern: Rails 8.1+ floor. Read: /docs/developer/getting-started (The stack)."

        NO_BUNDLER = "import maps and tailwindcss-rails, no bundler"
        REPLACED = {
          "devise" => "Rails' built-in authentication",
          "webpacker" => NO_BUNDLER, "shakapacker" => NO_BUNDLER,
          "jsbundling-rails" => NO_BUNDLER, "cssbundling-rails" => NO_BUNDLER,
          "react-rails" => "Hotwire", "react_on_rails" => "Hotwire",
          "sprockets" => "Propshaft", "sprockets-rails" => "Propshaft",
          "sidekiq" => "Solid Queue", "resque" => "Solid Queue", "good_job" => "Solid Queue",
          "delayed_job" => "Solid Queue", "delayed_job_active_record" => "Solid Queue"
        }.freeze
        # Any 8.1 release satisfies a requirement that admits the floor.
        FLOOR_PROBE = Gem::Version.new("8.1.99999")

        RESTRICT_ON_SEND = %i[gem].freeze

        def on_send(node)
          name = node.first_argument
          return unless name&.str_type?

          if REPLACED.key?(name.value)
            add_offense(node, message: format(MSG_GEM, gem: name.value, replacement: REPLACED[name.value]))
          elsif name.value == "rails"
            check_rails_floor(node)
          end
        end

        private

        def check_rails_floor(node)
          requirements = node.arguments.drop(1).select(&:str_type?).map(&:value)
          return if requirements.empty?
          return if Gem::Requirement.new(requirements).satisfied_by?(FLOOR_PROBE)

          add_offense(node, message: format(MSG_RAILS, requirement: requirements.map(&:inspect).join(", ")))
        rescue Gem::Requirement::BadRequirementError
          nil
        end
      end
    end
  end
end
