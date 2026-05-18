require "rails_helper"
require "json"
require "yaml"

# modelrails_base is an application template intended to be forked. Every
# default the template ships propagates into every downstream fork.
#
# This spec asserts the structural invariants that came out of the 8-reviewer
# panel review on 2026-05-18 (see docs/superpowers/specs/2026-05-18-devcontainer-
# dockerfile-cleanup-design.md). Each invariant catches a class of subtle
# misconfiguration that would otherwise propagate silently to downstream apps:
#
#   - Ruby version drift between .tool-versions, Gemfile, Gemfile.lock, and
#     the production Dockerfile (Aaron Patterson)
#   - Test gems leaking into the production image (Eileen Uchitelle)
#   - Dockerfile layer-cache invalidation from vendor/ COPY ordering (Nick
#     Janetakis + 3 others)
#   - Dev/prod base-image divergence (Nick Janetakis)
#   - Devcontainer that can't run `kamal deploy` (Donal McBreen)
#   - setup.sh that reimplements bin/setup instead of wrapping it (Justin
#     Searls)
#   - Missing onboarding signals like .env.example (Chris Oliver)
#   - Unused free perf: YJIT, MALLOC_CONF (Aaron Patterson)
RSpec.describe "Template invariants" do
  let(:root) { Rails.root }

  describe "Ruby version pinning is consistent across all sources of truth" do
    let(:tool_versions) { File.read(root.join(".tool-versions")) }
    let(:gemfile) { File.read(root.join("Gemfile")) }
    let(:gemfile_lock) { File.read(root.join("Gemfile.lock")) }
    let(:dockerfile) { File.read(root.join("Dockerfile")) }
    let(:deploy_yml) { File.read(root.join("config/deploy.yml")) }

    let(:tool_versions_ruby) do
      tool_versions[/^ruby\s+(\S+)/, 1]
    end

    it ".tool-versions pins a Ruby version" do
      expect(tool_versions_ruby).to be_present,
        "expected .tool-versions to declare `ruby <version>` on a line of its own"
    end

    it "Gemfile reads Ruby version from .tool-versions (Bundler is the enforcer)" do
      expect(gemfile).to match(/^ruby\s+file:\s+["']\.tool-versions["']/),
        "expected Gemfile to contain `ruby file: \".tool-versions\"` so Bundler enforces " \
        "the Ruby version everywhere bundle install runs (dev, CI, prod)"
    end

    it "Gemfile.lock captures the Ruby version in a RUBY VERSION block" do
      expect(gemfile_lock).to match(/^RUBY VERSION\n\s+ruby\s+#{Regexp.escape(tool_versions_ruby)}/),
        "expected Gemfile.lock to contain a RUBY VERSION block matching .tool-versions " \
        "(#{tool_versions_ruby}); regenerate with `bundle install`"
    end

    it "Dockerfile ARG RUBY_VERSION matches .tool-versions" do
      expect(dockerfile).to match(/^ARG RUBY_VERSION=#{Regexp.escape(tool_versions_ruby)}\b/),
        "expected Dockerfile ARG RUBY_VERSION to equal .tool-versions Ruby (#{tool_versions_ruby})"
    end

    it "Dockerfile comment references .tool-versions (not the obsolete .ruby-version)" do
      expect(dockerfile).to include(".tool-versions"),
        "expected Dockerfile to reference .tool-versions in its comments"
      expect(dockerfile).not_to match(/\.ruby-version/),
        "Dockerfile still references the obsolete .ruby-version file"
    end

    it "config/deploy.yml builder.args.RUBY_VERSION matches .tool-versions" do
      deploy = YAML.safe_load(deploy_yml, aliases: true, permitted_classes: [ Symbol ])
      ruby_version_arg = deploy.dig("builder", "args", "RUBY_VERSION")

      expect(ruby_version_arg).to eq(tool_versions_ruby),
        "expected config/deploy.yml builder.args.RUBY_VERSION (#{ruby_version_arg.inspect}) " \
        "to equal .tool-versions Ruby (#{tool_versions_ruby}); uncomment and wire the args block"
    end
  end

  describe "Production Dockerfile hygiene" do
    let(:dockerfile) { File.read(root.join("Dockerfile")) }
    let(:dockerfile_lines) { dockerfile.lines.map(&:chomp) }

    def line_index(pattern)
      dockerfile_lines.find_index { |line| line.match?(pattern) }
    end

    it "excludes both development AND test gem groups from the production image" do
      expect(dockerfile).to match(/BUNDLE_WITHOUT="development:test"/),
        "expected BUNDLE_WITHOUT to exclude both development AND test; otherwise rspec-rails, " \
        "capybara, playwright-ruby-client etc. ship to production in every fork"
    end

    it "sets MALLOC_CONF for jemalloc tuning (tighter RSS on long-running Puma workers)" do
      expect(dockerfile).to match(/MALLOC_CONF=.*dirty_decay_ms:1000/),
        "expected Dockerfile ENV block to set MALLOC_CONF including dirty_decay_ms:1000"
      expect(dockerfile).to match(/MALLOC_CONF=.*muzzy_decay_ms:0/),
        "expected MALLOC_CONF to include muzzy_decay_ms:0"
    end

    it "copies Gemfile and runs bundle install BEFORE copying vendor/" do
      gemfile_copy = line_index(/^COPY Gemfile/)
      bundle_install = line_index(/^\s*RUN bundle install/)
      vendor_copy = line_index(/^COPY vendor\b/)

      expect(gemfile_copy).not_to be_nil, "expected a `COPY Gemfile ...` line"
      expect(bundle_install).not_to be_nil, "expected a `RUN bundle install` line"
      expect(vendor_copy).not_to be_nil, "expected a `COPY vendor/...` line"

      expect(gemfile_copy).to be < bundle_install,
        "Gemfile must be copied before bundle install runs"
      expect(bundle_install).to be < vendor_copy,
        "bundle install must run before COPY vendor/ to preserve layer cache " \
        "across vendor/ changes (e.g., markdowndocs symlink updates)"
    end
  end

  describe "Devcontainer matches production runtime (Option C: shared base image)" do
    let(:devcontainer_path) { root.join(".devcontainer/devcontainer.json") }
    let(:devcontainer) do
      raw = File.read(devcontainer_path)
      # devcontainer.json is JSONC (supports `//` line comments). Strip them
      # before handing to JSON.parse so this spec doesn't care whether the
      # file uses comments or not.
      stripped = raw.gsub(%r{^\s*//[^\n]*$}, "")
      JSON.parse(stripped)
    end
    let(:setup_sh) { File.read(root.join(".devcontainer/setup.sh")) }

    it "uses ruby:<.tool-versions>-slim as the base image to match production" do
      tool_versions_ruby = File.read(root.join(".tool-versions"))[/^ruby\s+(\S+)/, 1]

      expect(devcontainer["image"]).to eq("docker.io/library/ruby:#{tool_versions_ruby}-slim"),
        "expected devcontainer image to share the production Dockerfile's base image " \
        "(runtime parity for libvips, glibc, sqlite3, OpenSSL versions)"
    end

    it "does not include the mise feature (Ruby is now baked into the base image)" do
      mise_feature_keys = (devcontainer["features"] || {}).keys.select { |k| k.include?("mise") }

      expect(mise_feature_keys).to be_empty,
        "expected no mise-related feature in devcontainer.json; the ruby:slim base image " \
        "ships Ruby directly. Found: #{mise_feature_keys.inspect}"
    end

    it "enables docker-outside-of-docker so `kamal deploy` works from inside the devcontainer" do
      docker_keys = (devcontainer["features"] || {}).keys.grep(/docker-outside-of-docker/)

      expect(docker_keys).not_to be_empty,
        "expected docker-outside-of-docker feature so forkers can run `kamal deploy` from " \
        "their devcontainer (otherwise: no Docker socket = opaque wall)"
    end

    it "mounts a named volume for the bundle cache (survives container rebuilds)" do
      mounts = Array(devcontainer["mounts"])

      expect(mounts).to include(match(/modelrails-bundle-cache/)),
        "expected a named volume mount for /usr/local/bundle to avoid re-installing gems " \
        "on every devcontainer rebuild. Mounts: #{mounts.inspect}"
    end

    it "forwards ports for Rails and common dev services" do
      expect(Array(devcontainer["forwardPorts"])).to include(3000),
        "expected port 3000 forwarded for Rails"
      expect(Array(devcontainer["forwardPorts"])).to include(1080),
        "expected port 1080 forwarded for Letter Opener Web (common forker add)"
    end

    it "labels forwarded ports via portsAttributes for visibility in VS Code's Ports panel" do
      attrs = devcontainer["portsAttributes"] || {}
      expect(attrs).to have_key("3000"),
        "expected portsAttributes.3000 entry with a label"
      expect(attrs.dig("3000", "label")).to be_present,
        "expected portsAttributes.3000.label so Rails is named in VS Code's Ports panel"
    end
  end

  describe ".devcontainer/setup.sh delegates to bin/setup (Rails convention)" do
    let(:setup_sh) { File.read(root.join(".devcontainer/setup.sh")) }

    it "invokes bin/setup rather than reimplementing its logic inline" do
      expect(setup_sh).to match(/bin\/setup/),
        "expected setup.sh to invoke `bin/setup` (Rails convention) instead of re-rolling " \
        "bundle install + db:prepare in shell"
    end

    it "no longer runs `mise install` (Ruby is in the base image now)" do
      expect(setup_sh).not_to match(/mise\s+install/),
        "setup.sh still calls `mise install`; the ruby:slim base image makes this unnecessary"
    end

    it "installs system packages that mirror the production Dockerfile" do
      expect(setup_sh).to include("apt-get install"),
        "expected setup.sh to apt-get install dev system packages"

      required_pkgs = %w[build-essential libjemalloc2 libvips sqlite3 libyaml-dev pkg-config]
      required_pkgs.each do |pkg|
        expect(setup_sh).to include(pkg),
          "expected system package `#{pkg}` in setup.sh (mirrors production Dockerfile)"
      end
    end

    it "prints next-steps guidance pointing forkers at .env.example and bin/dev" do
      expect(setup_sh).to include("Next steps"),
        "expected setup.sh to print a 'Next steps' block after install completes"
      expect(setup_sh).to include(".env.example"),
        "expected setup.sh next-steps to reference .env.example"
      expect(setup_sh).to include("bin/dev"),
        "expected setup.sh next-steps to point at `bin/dev` as the run command"
    end
  end

  describe "Onboarding completeness (the fork-and-run experience)" do
    let(:env_example_path) { root.join(".env.example") }
    let(:application_rb) { File.read(root.join("config/application.rb")) }

    it ".env.example exists in the repo root" do
      expect(File.exist?(env_example_path)).to be(true),
        "expected .env.example at repo root so forkers know which env vars matter"
    end

    it ".env.example documents RAILS_MASTER_KEY (Rails secret loading)" do
      env_example = File.read(env_example_path)
      expect(env_example).to include("RAILS_MASTER_KEY"),
        "expected .env.example to document RAILS_MASTER_KEY"
    end

    it ".env.example documents KAMAL_REGISTRY_PASSWORD (Kamal deploy)" do
      env_example = File.read(env_example_path)
      expect(env_example).to include("KAMAL_REGISTRY_PASSWORD"),
        "expected .env.example to document KAMAL_REGISTRY_PASSWORD"
    end

    it "config/application.rb enables YJIT (Rails 8.1 free perf)" do
      expect(application_rb).to match(/config\.yjit\s*=\s*true/),
        "expected config.yjit = true in config/application.rb (Rails 8.1+ free perf on supported Ruby)"
    end
  end
end
