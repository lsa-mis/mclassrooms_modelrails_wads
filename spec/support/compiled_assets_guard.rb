# System specs load the compiled Tailwind stylesheet from the test server. When
# it is missing, axe reports contrast violations on every page and interaction
# specs fail on collapsed layout — 132 failures that name neither Tailwind nor
# assets. Fail once, up front, with the command that fixes it instead.
#
# The hole is easy to fall into: tailwindcss-rails enhances `assets:clobber`
# with `tailwindcss:clobber`, so bin/setup's deliberate Propshaft heal deletes
# the stylesheet. The gem's counterpart safety net enhances `test:prepare`,
# which is the Minitest path — `bundle exec rspec` never invokes it.
module CompiledAssetsGuard
  class MissingCompiledAssetsError < StandardError; end

  BUILD_COMMAND = "bin/rails tailwindcss:build".freeze
  DEFAULT_STYLESHEET = "app/assets/builds/tailwind.css".freeze

  module_function

  # Read-only by design. Building here would race: bin/parallel-rspec boots one
  # RSpec process per core, and concurrent writers to a single CSS file is the
  # exact failure lefthook.yml orders its pre-push commands to avoid.
  def verify!(stylesheet = Rails.root.join(DEFAULT_STYLESHEET))
    stylesheet = Pathname.new(stylesheet)
    return if stylesheet.exist? && stylesheet.size.positive?

    raise MissingCompiledAssetsError, <<~MESSAGE
      Compiled Tailwind stylesheet missing or empty:
        #{stylesheet}

      System specs render unstyled without it, so axe reports contrast
      violations and layout-dependent interactions fail — none of which
      mention assets. Build it, then re-run:

        #{BUILD_COMMAND}

      `bin/setup` clears compiled assets and only rebuilds them by starting
      the dev server, so `bin/setup --skip-server` leaves this state behind.
    MESSAGE
  end
end
