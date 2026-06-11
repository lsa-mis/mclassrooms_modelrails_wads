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

    it "COPYs .tool-versions alongside Gemfile so the `ruby file:` directive resolves at bundle install" do
      # The Gemfile uses `ruby file: ".tool-versions"` (asserted above). When
      # Bundler parses the Gemfile inside `RUN bundle install`, it must be
      # able to resolve that file — so .tool-versions has to land in /rails
      # before bundle install runs, not later via `COPY . .`.
      #
      # Caught by the manual `docker build .` smoke test post-#129. The build
      # failed with: "Could not find version file .tool-versions. Bundler
      # cannot continue."
      gemfile_copy_line_index = dockerfile_lines.find_index { |l| l.match?(/^COPY Gemfile/) }
      expect(gemfile_copy_line_index).not_to be_nil, "expected a `COPY Gemfile ...` line"

      copy_line = dockerfile_lines[gemfile_copy_line_index]
      expect(copy_line).to include(".tool-versions"),
        "Gemfile uses `ruby file: \".tool-versions\"`, so the Dockerfile must COPY " \
        ".tool-versions alongside Gemfile or `bundle install` aborts. Current COPY at " \
        "Dockerfile:#{gemfile_copy_line_index + 1}: `#{copy_line.strip}`. " \
        "Fix: `COPY Gemfile Gemfile.lock .tool-versions ./`"
    end

    it "gates bootsnap precompile parallelism on cross-arch detection (Aaron Patterson)" do
      # rails/bootsnap#495 requires -j 1 only when cross-compiling under QEMU
      # emulation (TARGETPLATFORM != BUILDPLATFORM). On native CI builds the
      # default parallel compilation is a real wall-clock win.
      expect(dockerfile).to match(/^ARG TARGETPLATFORM/),
        "expected `ARG TARGETPLATFORM` in Dockerfile so BuildKit populates the value " \
        "(required to gate bootsnap parallelism on cross-arch detection)"
      expect(dockerfile).to match(/^ARG BUILDPLATFORM/),
        "expected `ARG BUILDPLATFORM` in Dockerfile to pair with TARGETPLATFORM"

      # The conditional must reference both ARGs together (any comparison
      # form: equality on native, inequality on cross-arch).
      expect(dockerfile).to match(/TARGETPLATFORM.*BUILDPLATFORM|BUILDPLATFORM.*TARGETPLATFORM/),
        "expected Dockerfile to compare TARGETPLATFORM and BUILDPLATFORM to decide " \
        "whether bootsnap precompile uses -j 1 (cross-compile) or default parallelism (native)"
    end

    it "ships app code root-owned and chowns only the dirs Rails writes at runtime" do
      # Defense in depth (upstream Rails 8.1 pattern): a compromised runtime
      # process must not be able to rewrite app code or gems. `COPY --chown`
      # of the whole /rails tree makes every file writable by the rails user;
      # instead copy root-owned and chown only db/log/storage/tmp.
      expect(dockerfile).not_to match(/^COPY --chown=rails:rails/),
        "expected runtime COPYs to leave files root-owned (read-only to the rails user); " \
        "`COPY --chown=rails:rails` makes the entire app tree writable by the runtime user"
      expect(dockerfile).to match(/chown -R rails:rails db log storage tmp/),
        "expected `chown -R rails:rails db log storage tmp` so the only dirs Rails " \
        "writes at runtime (db:prepare, logs, Active Storage, bootsnap cache/pids) are writable"

      copy_rails = line_index(%r{^COPY --from=build /rails /rails})
      chown = line_index(/chown -R rails:rails/)
      user = line_index(/^USER 1000:1000/)

      expect(copy_rails).not_to be_nil, "expected `COPY --from=build /rails /rails` in the final stage"
      expect(chown).not_to be_nil
      expect(user).not_to be_nil

      expect(copy_rails).to be < chown,
        "the /rails COPY must land before the chown (the dirs must exist to be chowned)"
      expect(chown).to be < user,
        "USER 1000:1000 must come after the chown so the ownership change runs as root"
    end

    it "applies Debian security updates in the base stage (apt-get upgrade)" do
      # Docker Hub rebuilds ruby:slim on Debian point releases, NOT on interim
      # security updates — so a freshly pulled base can still carry packages
      # Debian already fixed (first image scan caught an OpenSSL heap UAF and
      # a poppler overflow exactly this way). `apt-get upgrade -y` in our own
      # base stage is the only reliable patch path between base rebuilds.
      expect(dockerfile).to match(/apt-get upgrade -y/),
        "expected `apt-get upgrade -y` in the base stage so Debian security fixes land " \
        "even when the ruby:slim base image lags the Debian repos"
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

  describe "CI verifies the production image actually builds (closes #129/#132 gap)" do
    # Structural specs cannot detect build-time bugs like the .tool-versions
    # COPY regression from #129 (fixed in #132). The only safety net for that
    # class of bug is running `docker build .` in CI. These assertions ensure
    # that safety net stays wired up.
    let(:ci_workflow_path) { root.join(".github/workflows/ci.yml") }
    let(:ci_workflow) { YAML.safe_load(File.read(ci_workflow_path), aliases: true) }
    let(:docker_build_job) { ci_workflow.dig("jobs", "docker_build") }

    it "has a docker_build job in .github/workflows/ci.yml" do
      expect(docker_build_job).not_to be_nil,
        "expected a `docker_build` job in CI so the production Dockerfile is verified to " \
        "build on every PR. Without this, build-time regressions can ship to main (see #129 -> #132)."
    end

    it "docker_build job uses Buildx + build-push-action for native GHA layer caching" do
      next if docker_build_job.nil?

      uses_steps = Array(docker_build_job["steps"]).map { |s| s["uses"].to_s }

      expect(uses_steps).to include(match(%r{docker/setup-buildx-action})),
        "expected docker/setup-buildx-action to enable BuildKit features (cache-from/cache-to gha)"
      expect(uses_steps).to include(match(%r{docker/build-push-action})),
        "expected docker/build-push-action to run the build (with GHA cache integration)"
    end

    it "docker_build caches layers across CI runs (otherwise it's a 3-5 min wall on every PR)" do
      next if docker_build_job.nil?

      build_step = Array(docker_build_job["steps"]).find do |s|
        s["uses"].to_s.include?("docker/build-push-action")
      end
      next if build_step.nil?

      cache_from = build_step.dig("with", "cache-from").to_s
      expect(cache_from).to include("type=gha"),
        "expected cache-from: type=gha for layer reuse across CI runs " \
        "(without it, every PR pays the full 3-5 min cold build cost)"
    end
  end

  describe "CI scans the production image for OS-level CVEs" do
    # brakeman covers app code and bundler-audit covers gem deps, but neither
    # sees the OS packages baked into ruby:slim (glibc, openssl, sqlite3,
    # libvips). The image scan is the third layer. Policy: it runs on
    # Dockerfile-affecting PRs plus a weekly schedule — NOT on every PR —
    # because new base-image CVEs appear without any code change and would
    # red-flag unrelated green branches (same drift mode as the 2026-06-09
    # bundler-audit oauth2 CVE).
    let(:scan_workflow_path) { root.join(".github/workflows/image_scan.yml") }
    let(:scan_workflow_raw) { File.read(scan_workflow_path) }
    let(:scan_workflow) { YAML.safe_load(scan_workflow_raw, aliases: true) }
    # Psych (YAML 1.1) parses the unquoted `on:` trigger key as boolean true.
    let(:triggers) { scan_workflow[true] }
    let(:scan_job) { scan_workflow.dig("jobs", "scan_image") }
    let(:scan_steps) { Array(scan_job && scan_job["steps"]) }

    it "has an image_scan workflow with a scan_image job" do
      expect(File.exist?(scan_workflow_path)).to be(true),
        "expected .github/workflows/image_scan.yml — without it, OS-package CVEs in the " \
        "production image are invisible (brakeman/bundler-audit don't scan the image layer)"
      expect(scan_job).not_to be_nil, "expected a `scan_image` job in image_scan.yml"
    end

    it "runs weekly AND on Dockerfile-affecting PRs (not every PR)" do
      expect(triggers).to include("schedule"),
        "expected a schedule trigger so new base-image CVEs surface without waiting " \
        "for the next Dockerfile change"
      expect(triggers.dig("pull_request", "paths")).to include("Dockerfile"),
        "expected pull_request.paths to include Dockerfile so image-affecting changes " \
        "are scanned pre-merge"
    end

    it "builds with the shared GHA layer cache and loads the image for the scanner" do
      build_step = scan_steps.find { |s| s["uses"].to_s.include?("docker/build-push-action") }
      expect(build_step).not_to be_nil, "expected a docker/build-push-action build step"

      expect(build_step.dig("with", "cache-from").to_s).to include("type=gha"),
        "expected cache-from: type=gha so the scan reuses docker_build's layers " \
        "instead of paying a cold build"
      expect(build_step.dig("with", "load")).to be(true),
        "expected load: true — without it the image exists only in the build cache " \
        "and the scanner has nothing to scan"
    end

    it "scheduled runs bypass the layer cache (a cached apt layer hides current package state)" do
      # The first real scan proved this: the GHA-cached apt layer carried
      # OpenSSL/poppler packages that Debian had already fixed. A weekly scan
      # against cached layers answers "what did we build last time", not
      # "what would we ship if we rebuilt today".
      build_step = scan_steps.find { |s| s["uses"].to_s.include?("docker/build-push-action") }
      next if build_step.nil?

      no_cache = build_step.dig("with", "no-cache").to_s
      expect(no_cache).to include("schedule"),
        "expected no-cache to be conditional on the schedule event " \
        "(e.g. no-cache: ${{ github.event_name == 'schedule' }})"
    end

    it ".trivyignore entries each carry a rationale and a Revisit marker" do
      # The exception path only works if exceptions stay temporary and
      # explained. Every ignored CVE needs (a) a comment block above it and
      # (b) an explicit `Revisit:` line so the entry has an expiry trigger.
      trivyignore = root.join(".trivyignore")
      next unless File.exist?(trivyignore)

      blocks = File.read(trivyignore).split(/\n\s*\n/)
      cve_blocks = blocks.select { |b| b.match?(/^(CVE|GHSA)-/) }
      expect(cve_blocks).not_to be_empty, ".trivyignore exists but ignores nothing — delete it"

      cve_blocks.each do |block|
        cve = block[/^(?:CVE|GHSA)-\S+/]
        expect(block.lines.any? { |l| l.start_with?("#") }).to be(true),
          "#{cve}'s block has no comment — every ignored CVE needs a rationale"
        expect(block).to match(/Revisit:/i),
          "#{cve}'s block has no `Revisit:` line — exceptions need an expiry trigger"
      end
    end

    it "fails the run on fixable HIGH/CRITICAL CVEs (the policy gate)" do
      trivy_step = scan_steps.find { |s| s["uses"].to_s.include?("trivy-action") }
      expect(trivy_step).not_to be_nil, "expected an aquasecurity/trivy-action scan step"

      with = trivy_step["with"] || {}
      expect(with["severity"].to_s).to match(/CRITICAL/),
        "expected severity to include CRITICAL"
      expect(with["severity"].to_s).to match(/HIGH/),
        "expected severity to include HIGH"
      expect(with["exit-code"].to_s).to eq("1"),
        "expected exit-code: 1 so HIGH/CRITICAL findings fail the run (report-only scans rot)"
      expect(with["ignore-unfixed"]).to be(true),
        "expected ignore-unfixed: true — Debian-stable bases always carry unfixed CVEs; " \
        "gating on them would make the scan permanently red and ignored"
    end
  end

  describe "Production topology safety (Rosa Gutiérrez + Ops panel, #130)" do
    # SQLite-on-Rails templates have non-obvious deploy hazards: rolling deploys
    # can race two containers on the same SQLite file; recurring jobs running in
    # Puma can be SIGKILL'd before draining; mailer jobs head-of-line-block
    # sweep jobs when they share a queue. These assertions encode the panel's
    # consensus decisions so forkers inherit safe defaults.
    let(:deploy_yml_raw) { File.read(root.join("config/deploy.yml")) }
    let(:deploy_yml) { YAML.safe_load(deploy_yml_raw, aliases: true, permitted_classes: [ Symbol ]) }
    let(:queue_yml_raw) { File.read(root.join("config/queue.yml")) }
    let(:recurring_yml_raw) { File.read(root.join("config/recurring.yml")) }

    it "servers.web declares max-replicas: 1 (SQLite is single-writer, single-host)" do
      web_options = deploy_yml.dig("servers", "web", "options") || {}
      expect(web_options["max-replicas"]).to eq(1),
        "expected `servers.web.options.max-replicas: 1` so Kamal stops the old container " \
        "before starting the new one. Two containers writing to the same SQLite file is " \
        "corruption territory. (Donal McBreen)"
    end

    it "deploy.yml sets stop_wait_time so Solid Queue can drain gracefully on deploy" do
      expect(deploy_yml).to have_key("stop_wait_time"),
        "expected `stop_wait_time` at top level of deploy.yml. Default Kamal 30s isn't " \
        "enough for Solid Queue's on_worker_shutdown to drain in-flight jobs. (Rosa Gutiérrez)"
      expect(deploy_yml["stop_wait_time"]).to be >= 45,
        "expected stop_wait_time >= 45s for SK drain (got #{deploy_yml['stop_wait_time']})"
    end

    it "deploy.yml documents the SOLID_QUEUE_IN_PUMA graduation checklist for forkers" do
      # The default stays true (correct for one-box SQLite forks). The comment
      # must make the graduation path unmissable so forkers know when to flip it.
      # We just check both signals are present in the file — co-location is
      # enforced by being in the same env.clear block in practice.
      expect(deploy_yml_raw).to include("SOLID_QUEUE_IN_PUMA"),
        "expected SOLID_QUEUE_IN_PUMA referenced in deploy.yml"
      expect(deploy_yml_raw).to match(/[Gg]raduation\s+checklist|when\s+you\s+outgrow/),
        "expected deploy.yml to include an explicit graduation checklist explaining when to " \
        "flip SOLID_QUEUE_IN_PUMA and what else changes. The default propagates to every fork " \
        "— the comment is the documentation. (Donal McBreen)"
    end

    it "deploy.yml warns that the job: block requires migrating off SQLite" do
      # The currently-commented `servers.job:` block is a SQLite trap: SQLite is
      # single-host, so a separate job role can't share the DB file across
      # machines. The deploy.yml as a whole must warn forkers before they
      # uncomment that block.
      expect(deploy_yml_raw).to match(/^\s*#\s*job:/m),
        "expected a commented `# job:` block in deploy.yml"
      expect(deploy_yml_raw).to match(/SQLite.*(?:single-host|cannot.*share|trap|networked)|networked.*database.*job/im),
        "expected deploy.yml to warn that uncommenting the `job:` block requires a networked " \
        "DB (Postgres/MySQL accessory) — SQLite cannot be shared across hosts. " \
        "(Donal McBreen + Rosa Gutiérrez)"
    end

    it "queue.yml uses named queues for observability, not the queues: \"*\" wildcard" do
      queue = YAML.safe_load(queue_yml_raw, aliases: true)
      workers = queue.dig("default", "workers") || []
      expect(workers).not_to be_empty, "expected default.workers in queue.yml"

      queues_value = workers.first["queues"]
      expect(queues_value).to be_an(Array),
        "expected queues to be an explicit array (e.g., [default, mailers, low]) instead of " \
        "the \"*\" wildcard — named queues give clear operational signals when one backs up. " \
        "Got: #{queues_value.inspect}"
      expect(queues_value).to include("mailers"),
        "expected `mailers` queue declared explicitly so mailer jobs are routable separately"
    end

    it "recurring.yml routes digest_mailer to the mailers queue" do
      recurring = YAML.safe_load(recurring_yml_raw, aliases: true)
      digest_mailer = recurring.dig("production", "digest_mailer") || {}

      expect(digest_mailer["queue"]).to eq("mailers"),
        "expected digest_mailer to be routed to the `mailers` queue so it shows up in " \
        "queue-level observability (was on `default` — sharing with DB sweep jobs)"
    end
  end

  describe "Devops architecture is documented for forkers (app/docs surface)" do
    # The template's devcontainer, deployment, and Solid Queue topology are
    # load-bearing decisions that propagate to every fork. Forkers need to
    # find this in app/docs/ (rendered at /docs via markdowndocs), not buried
    # in deploy.yml comments or a design spec. These assertions catch the
    # case where we change config but forget to update the doc surface.
    let(:deployment_doc_path) { root.join("app/docs/deployment.md") }
    let(:background_jobs_doc_path) { root.join("app/docs/background-jobs.md") }
    let(:getting_started_doc_path) { root.join("app/docs/getting-started.md") }

    it "app/docs/deployment.md exists and explains the Kamal+SQLite topology" do
      expect(File.exist?(deployment_doc_path)).to be(true),
        "expected app/docs/deployment.md so forkers find deployment guidance via /docs " \
        "(not just deploy.yml comments they only read mid-deploy)"

      content = File.read(deployment_doc_path)
      expect(content).to match(/max-replicas/i),
        "expected deployment.md to explain max-replicas: 1 SQLite constraint"
      expect(content).to match(/SOLID_QUEUE_IN_PUMA/),
        "expected deployment.md to document SOLID_QUEUE_IN_PUMA topology + graduation"
      expect(content).to match(/[Gg]raduation/),
        "expected deployment.md to spell out the graduation path from SQLite/Puma defaults"
      expect(content).to match(/stop_wait_time/),
        "expected deployment.md to explain stop_wait_time tuning for Solid Queue drain"
    end

    it "app/docs/background-jobs.md exists and documents Solid Queue topology" do
      expect(File.exist?(background_jobs_doc_path)).to be(true),
        "expected app/docs/background-jobs.md so forkers find queue topology + recurring " \
        "job guidance via /docs (not just queue.yml comments)"

      content = File.read(background_jobs_doc_path)
      expect(content).to match(/[Ss]olid [Qq]ueue/),
        "expected background-jobs.md to reference Solid Queue"
      expect(content).to match(/mailers/i),
        "expected background-jobs.md to document the `mailers` named queue"
      expect(content).to match(/default/i),
        "expected background-jobs.md to document the `default` queue convention"
    end

    it "app/docs/getting-started.md mentions the docker_build CI job" do
      content = File.read(getting_started_doc_path)
      expect(content).to match(/docker_build/),
        "expected getting-started.md Gate 2 CI table to include the `docker_build` job " \
        "added in #134. Without this, forkers don't realize their PRs are CI-verified " \
        "against a real production build."
    end
  end

  describe "Repo-level documentation surfaces exist" do
    # Forkers consult CHANGELOG.md to see what's changed between fork points.
    # Asserting its existence here prevents accidental deletion during repo
    # cleanup — a class of mistake easier to make than to spot.
    it "CHANGELOG.md exists at the repo root" do
      expect(File.exist?(root.join("CHANGELOG.md"))).to be(true),
        "expected CHANGELOG.md at the repo root so forkers can see what's changed " \
        "between fork points. Use Keep a Changelog format (https://keepachangelog.com)."
    end
  end
end
