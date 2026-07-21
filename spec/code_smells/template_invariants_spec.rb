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

    it "does not install Node (Cuprite drives Chrome from Ruby; nothing in the template needs Node)" do
      node_feature_keys = (devcontainer["features"] || {}).keys.grep(/node/)

      expect(node_feature_keys).to be_empty,
        "expected no Node feature in devcontainer.json — #497 removed Node from the template " \
        "(system specs use Cuprite/ferrum, a pure-Ruby CDP driver; linters are Ruby gems). " \
        "Found: #{node_feature_keys.inspect}"
    end

    it "enables docker-outside-of-docker so `kamal deploy` works from inside the devcontainer" do
      docker_keys = (devcontainer["features"] || {}).keys.grep(/docker-outside-of-docker/)

      expect(docker_keys).not_to be_empty,
        "expected docker-outside-of-docker feature so forkers can run `kamal deploy` from " \
        "their devcontainer (otherwise: no Docker socket = opaque wall)"
    end

    it "mounts a named volume for the bundle cache (survives container rebuilds)" do
      mounts = Array(devcontainer["mounts"])

      expect(mounts).to include(match(/bundle-cache/)),
        "expected a named volume mount for /usr/local/bundle to avoid re-installing gems " \
        "on every devcontainer rebuild. Mounts: #{mounts.inspect}"
    end

    it "forwards the Rails port" do
      expect(Array(devcontainer["forwardPorts"])).to include(3000),
        "expected port 3000 forwarded for Rails"
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

    it "installs a browser for Cuprite system specs without resurrecting Node (no npm/npx)" do
      expect(setup_sh).not_to match(/\bnpm\b|\bnpx\b|node_modules/),
        "setup.sh still references npm/npx/node_modules — #497 removed Node; the devcontainer " \
        "must not resurrect it"
      expect(setup_sh).to match(/chromium|google-chrome/),
        "expected setup.sh to apt-install a browser (chromium) for Cuprite system specs — the " \
        "ruby:slim base ships none (unlike CI's ubuntu-latest runners), so without it ferrum has " \
        "no browser to drive and every system spec fails in the devcontainer"
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

    # A fork dev copies .env.example; every ENV var the app reads that an
    # operator can meaningfully set should be there, so they aren't rediscovered
    # by grepping source (#298). Vars the harness/tooling sets — not a human
    # editing .env — are excluded here with a reason.
    excluded_env_vars = {
      "BUNDLE_GEMFILE"      => "set by Bundler, not an operator",
      "CI"                  => "set by the CI runner",
      "PIDFILE"             => "set by bin/dev / Foreman",
      "SOLID_QUEUE_IN_PUMA" => "set in config/deploy.yml env.clear, not .env (documented in deployment.md)",
      "TEST_ENV_NUMBER"     => "set by parallel_tests per worker (bin/parallel-rspec), never by a human"
    }

    it "documents every operator-settable ENV var the code reads (no rediscovery-by-grep)" do
      env_example = File.read(env_example_path)
      sources = Dir[root.join("{app,config,lib,db,bin}/**/*.{rb,yml,erb}")] + [ root.join("Rakefile").to_s ]
      read_vars = sources.flat_map do |file|
        File.read(file).scan(/ENV(?:\.fetch)?\s*[\[(]\s*["']([A-Z][A-Z0-9_]+)["']/).flatten
      end.uniq

      required = read_vars.reject { |var| excluded_env_vars.key?(var) }
      missing = required.reject { |var| env_example.include?(var) }

      expect(missing).to be_empty,
        "These ENV vars are read by the code but absent from .env.example — add them (grouped by " \
        "scope, with one-line comments), or add to excluded_env_vars with a reason: #{missing.sort.join(', ')}"
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

  describe "CI and Lefthook run the same integrity-gated parallel suite" do
    # CI and the local pre-push gate have drifted before (bundler-audit ran in
    # CI only — PR #371), so the invariant is: BOTH run bin/parallel-rspec,
    # which wraps parallel_tests with the example-count parity and merged
    # coverage gates. A raw `rspec` invocation in either place silently loses
    # those gates.
    let(:ci_workflow) { YAML.safe_load(File.read(root.join(".github/workflows/ci.yml")), aliases: true) }
    let(:lefthook_config) { YAML.safe_load(File.read(root.join("lefthook.yml")), aliases: true) }

    it "CI's test job runs bin/parallel-rspec" do
      run_steps = Array(ci_workflow.dig("jobs", "test", "steps")).map { |s| s["run"].to_s }
      expect(run_steps).to include(match(%r{bin/parallel-rspec})),
        "expected CI's test job to run bin/parallel-rspec (parallel suite + integrity gates); " \
        "a raw rspec invocation loses the example-count parity and merged-coverage gates"
    end

    it "Lefthook's pre-push rspec command runs bin/parallel-rspec" do
      run = lefthook_config.dig("pre-push", "commands", "rspec", "run").to_s
      expect(run).to include("bin/parallel-rspec"),
        "expected the pre-push rspec gate to run bin/parallel-rspec so local pushes " \
        "get the same gates as CI (drift bit us before — see lefthook.yml's bundler_audit note)"
    end
  end

  describe "CI cancels superseded runs (#486)" do
    # Without a concurrency group, a second push to a PR branch lets the stale
    # ~8-min run finish anyway — occupying runners and delaying the fresh run's
    # feedback. cancel-in-progress must be gated to pull_request events: pushes
    # to the default branch should each complete for the historical record.
    let(:ci_workflow) { YAML.safe_load(File.read(root.join(".github/workflows/ci.yml")), aliases: true) }

    it "declares a top-level concurrency block keyed on the branch/PR ref" do
      group = ci_workflow.dig("concurrency", "group").to_s
      expect(group).to include("github."),
        "expected a top-level concurrency.group keyed on the ref (e.g. github.head_ref || github.ref) " \
        "so all runs for one branch share a group and supersede each other"
    end

    it "cancels in-progress runs only for pull_request events" do
      cancel = ci_workflow.dig("concurrency", "cancel-in-progress").to_s
      expect(cancel).to include("github.event_name == 'pull_request'"),
        "expected cancel-in-progress gated to pull_request events so main-branch runs " \
        "are never cancelled mid-flight (each push to main completes for the record)"
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

  describe "CI persists the spec runtime log for balanced parallel splits (#488)" do
    # bin/parallel-rspec writes tmp/parallel_runtime_rspec.log (per-file spec
    # timings); parallel_tests reads it on the NEXT run to split work by measured
    # time instead of file size, evening out the slowest worker. That only helps
    # if the log survives between runs — so the test job must cache it. Without
    # the cache the log is cold every run and the split silently falls back to
    # file size (still correct, just unbalanced — the #488 regression).
    let(:ci_workflow) { YAML.safe_load(File.read(root.join(".github/workflows/ci.yml")), aliases: true) }
    let(:test_steps) { Array(ci_workflow.dig("jobs", "test", "steps")) }

    it "caches tmp/parallel_runtime_rspec.log across runs" do
      runtime_cache = test_steps.find do |step|
        step["uses"].to_s.include?("actions/cache") &&
          step.dig("with", "path").to_s.include?("parallel_runtime_rspec.log")
      end
      expect(runtime_cache).not_to be_nil,
        "expected an actions/cache step in the test job persisting " \
        "tmp/parallel_runtime_rspec.log so runtime-based worker balancing has a seed"
    end

    it "keys the cache so PRs restore the most recent recorded log" do
      runtime_cache = test_steps.find { |s| s.dig("with", "path").to_s.include?("parallel_runtime_rspec.log") }
      next if runtime_cache.nil?

      expect(runtime_cache.dig("with", "restore-keys").to_s).to be_present,
        "expected restore-keys on the runtime-log cache so a PR (whose exact key misses) " \
        "still restores the newest log from the base branch"
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

    it "database.yml declares journal_mode WAL explicitly so forks inherit the durability posture" do
      rendered = ERB.new(File.read(root.join("config/database.yml"))).result
      db = YAML.safe_load(rendered, aliases: true)

      expect(db.dig("default", "pragmas", "journal_mode")).to eq("wal"),
        "expected `pragmas: { journal_mode: wal }` in database.yml's default block. Rails 8.1 " \
        "defaults to WAL, but the template makes it explicit so a fork reads the production " \
        "durability/concurrency posture here instead of inferring it from adapter defaults " \
        "(Nate Berkopec, #304). `pragmas:` merges over Rails' DEFAULT_PRAGMAS — the other tuned " \
        "defaults (synchronous: normal, foreign_keys, mmap_size) are preserved."
      expect(db.dig("default", "timeout")).to eq(5000),
        "expected `timeout: 5000` — installs the sqlite3 busy handler so writers wait up to 5s " \
        "for the lock (NOT the busy_timeout PRAGMA; see spec/config/sqlite_pragmas_spec.rb)"
    end
  end

  describe "Devops architecture is documented for forkers (app/docs surface)" do
    # The template's devcontainer, deployment, and Solid Queue topology are
    # load-bearing decisions that propagate to every fork. Forkers need to
    # find this in app/docs/ (rendered at /docs via markdowndocs), not buried
    # in deploy.yml comments or a design spec. These assertions catch the
    # case where we change config but forget to update the doc surface.
    let(:deployment_doc_path) { root.join("app/docs/developer/deployment.md") }
    let(:background_jobs_doc_path) { root.join("app/docs/developer/background-jobs.md") }
    let(:getting_started_doc_path) { root.join("app/docs/developer/getting-started.md") }

    it "app/docs/developer/deployment.md exists and explains the Kamal+SQLite topology" do
      expect(File.exist?(deployment_doc_path)).to be(true),
        "expected app/docs/developer/deployment.md so forkers find deployment guidance via /docs/developer/deployment " \
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

    it "app/docs/developer/background-jobs.md exists and documents Solid Queue topology" do
      expect(File.exist?(background_jobs_doc_path)).to be(true),
        "expected app/docs/developer/background-jobs.md so forkers find queue topology + recurring " \
        "job guidance via /docs/developer/background-jobs (not just queue.yml comments)"

      content = File.read(background_jobs_doc_path)
      expect(content).to match(/[Ss]olid [Qq]ueue/),
        "expected background-jobs.md to reference Solid Queue"
      expect(content).to match(/mailers/i),
        "expected background-jobs.md to document the `mailers` named queue"
      expect(content).to match(/default/i),
        "expected background-jobs.md to document the `default` queue convention"
    end

    it "app/docs/developer/getting-started.md mentions the docker_build CI job" do
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

  describe "the template ships zero encrypted credential blobs" do
    # A committed .yml.enc is undecryptable dead weight to every fork and a
    # guaranteed merge conflict whenever upstream rotates a secret. Forks
    # generate per-environment credentials on day one (README "Forking this
    # template") and may commit their own blobs in their private repos.
    it "tracks no credential blobs or keys in git" do
      tracked = `git -C #{root} ls-files config`.lines.map(&:strip)
      offenders = tracked.grep(/\.yml\.enc\z|master\.key\z|credentials\/.*\.key\z/)
      expect(offenders).to be_empty,
        "expected no encrypted credential blobs or keys tracked in git, found: " \
        "#{offenders.join(', ')}. The template ships zero credentials; see README."
    end
  end

  describe "Fork seams (downstream disentanglement — see /docs/developer/forking)" do
    it "keeps brand identity strings in the fork-owned brand locale file" do
      brand_path = Rails.root.join("config/locales/en/brand.en.yml")
      expect(File.exist?(brand_path)).to be(true),
        "expected config/locales/en/brand.en.yml — the fork-owned home of brand strings (see /docs/developer/forking)"
      brand = YAML.load_file(brand_path)
      expect(brand.dig("en", "application", "name")).to be_present,
        "expected en.application.name in config/locales/en/brand.en.yml — brand identity strings live in the fork-owned file (see /docs/developer/forking)"
      expect(brand.dig("en", "application", "description")).to be_present,
        "expected en.application.description in config/locales/en/brand.en.yml — brand identity strings live in the fork-owned file (see /docs/developer/forking)"
      expect(brand.dig("en", "footer", "copyright")).to be_present,
        "expected en.footer.copyright in config/locales/en/brand.en.yml — brand identity strings live in the fork-owned file (see /docs/developer/forking)"
    end

    it "defines no brand strings in template-owned locale files (forks edit brand.en.yml only)" do
      app_locale = YAML.load_file(Rails.root.join("config/locales/en/application.en.yml"))
      expect(app_locale.dig("en", "application", "name")).to be_nil,
        "expected en.application.name to be absent from config/locales/en/application.en.yml — " \
        "brand strings must live in brand.en.yml so forks edit one file without touching template-owned locales (see /docs/developer/forking)"
      expect(app_locale.dig("en", "application", "description")).to be_nil,
        "expected en.application.description to be absent from config/locales/en/application.en.yml — " \
        "brand strings must live in brand.en.yml so forks edit one file without touching template-owned locales (see /docs/developer/forking)"
      expect(app_locale.dig("en", "footer", "copyright")).to be_nil,
        "expected en.footer.copyright to be absent from config/locales/en/application.en.yml — " \
        "brand strings must live in brand.en.yml so forks edit one file without touching template-owned locales (see /docs/developer/forking)"
    end

    it "still resolves the brand translations after the move (the views did not change)" do
      expect(I18n.exists?("application.name")).to be(true),
        "expected I18n key application.name to resolve — brand.en.yml must define en.application.name " \
        "so views using t('application.name') keep working after the brand-seam split (see /docs/developer/forking)"
      expect(I18n.exists?("application.description")).to be(true),
        "expected I18n key application.description to resolve — brand.en.yml must define en.application.description " \
        "so views using t('application.description') keep working after the brand-seam split (see /docs/developer/forking)"
      expect(I18n.exists?("footer.copyright")).to be(true),
        "expected I18n key footer.copyright to resolve — brand.en.yml must define en.footer.copyright " \
        "so views using t('footer.copyright') keep working after the brand-seam split (see /docs/developer/forking)"
    end

    it "draws product routes from the fork-owned config/routes/app.rb" do
      expect(File.read(Rails.root.join("config/routes.rb"))).to include("draw(:app)"),
        "expected config/routes.rb to call draw(:app) — product routes live in the fork-owned config/routes/app.rb (see /docs/developer/forking)"
      app_routes_path = Rails.root.join("config/routes/app.rb")
      expect(File.exist?(app_routes_path)).to be(true),
        "expected config/routes/app.rb — the fork-owned home of product routes (see /docs/developer/forking)"
      expect(File.read(app_routes_path)).to include('root "pages#home"'),
        "expected the root route in config/routes/app.rb — it moved there from config/routes.rb (see /docs/developer/forking)"
    end

    it "marks fork-owned paths merge=ours so upstream syncs keep the fork's version" do
      gitattributes = File.read(Rails.root.join(".gitattributes"))
      %w[
        app/views/pages/**
        app/controllers/pages_controller.rb
        config/locales/en/pages.en.yml
        config/locales/en/brand.en.yml
        config/routes/app.rb
        config/markdowndocs_categories.local.yml
        app/assets/tailwind/tokens/_brand.css
        README.md
      ].each do |path|
        expect(gitattributes).to match(/^#{Regexp.escape(path)} merge=ours$/),
          "expected .gitattributes to mark #{path} merge=ours"
      end
    end

    it "activates the fork merge driver from bin/setup, gated on the upstream remote" do
      setup_script = File.read(Rails.root.join("bin/setup"))
      expect(setup_script).to include("merge.ours.driver"),
        "bin/setup must activate the merge=ours driver for forks"
      expect(setup_script).to include("git remote get-url upstream"),
        "driver activation must be gated on an upstream remote existing — " \
        "the template repo itself must never set the driver"
    end

    it "marks the fork extension point in db/seeds.rb" do
      expect(File.read(Rails.root.join("db/seeds.rb")))
        .to include("Fork seam: add your app's domain seeds BELOW this line"),
        "db/seeds.rb needs the end-of-template marker so forks add seeds below it (see /docs/developer/forking)"
    end

    it "documents every merge=ours path in the forking guide (no silent contract drift)" do
      gitattributes = File.read(Rails.root.join(".gitattributes"))
      guide = File.read(Rails.root.join("app/docs/developer/forking.md"))
      gitattributes.scan(/^(\S+) merge=ours$/).flatten.each do |path|
        expect(guide).to include(path),
          "#{path} is marked merge=ours in .gitattributes but not mentioned in app/docs/developer/forking.md"
      end
    end

    it "hardcodes the brand name in no template-owned locale file (sweep beyond application.en.yml)" do
      brand_name = YAML.load_file(Rails.root.join("config/locales/en/brand.en.yml"))
        .dig("en", "application", "name")
      fork_owned = %w[config/locales/en/brand.en.yml config/locales/en/pages.en.yml]
        .map { |path| Rails.root.join(path).to_s }
      Dir[Rails.root.join("config/locales/**/*.yml")].sort.reject { |file| fork_owned.include?(file) }.each do |file|
        expect(File.read(file)).not_to include(brand_name),
          "#{file.delete_prefix("#{Rails.root}/")} hardcodes the brand name #{brand_name.inspect} — " \
          "brand strings live only in fork-owned brand.en.yml (see /docs/developer/forking)"
      end
    end

    it "lets forks override brand colors in a fork-owned file imported after the template defaults" do
      brand_css = Rails.root.join("app/assets/tailwind/tokens/_brand.css")
      expect(File.exist?(brand_css)).to be(true),
        "expected app/assets/tailwind/tokens/_brand.css — the fork-owned brand-color override file (see /docs/developer/forking)"

      app_css = File.read(Rails.root.join("app/assets/tailwind/application.css"))
      primitives_at = app_css.index("./tokens/_primitives.css")
      brand_at = app_css.index("./tokens/_brand.css")
      expect(brand_at).not_to be_nil,
        "application.css must @import ./tokens/_brand.css so a fork's color overrides take effect"
      expect(brand_at).to be > primitives_at,
        "_brand.css must be imported AFTER _primitives.css so a fork's overrides win the cascade (see docs/theming.md)"
    end
  end

  describe "CI lint tooling is version-pinned (no silent drift across CI, local, and forks)" do
    # Was npm-based (package.json + package-lock.json), replaced with Ruby
    # gems (erb_lint, mdl) — Bundler/Gemfile.lock pin exact versions the same
    # way, and `bundle exec` doesn't have npm's "unpinned global install"
    # footgun (see #299) at all, so there's no equivalent failure mode to
    # guard against there.
    let(:gemfile_lock) { File.read(root.join("Gemfile.lock")) }

    it "pins the lint gems in Gemfile.lock at an exact resolved version" do
      %w[erb_lint mdl].each do |gem_name|
        expect(gemfile_lock).to match(/^\s+#{Regexp.escape(gem_name)}\s+\(\d+\.\d+\.\d+\)/),
          "expected #{gem_name} pinned to an exact resolved version in Gemfile.lock, " \
          "so CI, local, and forks run the same linter"
      end
    end

    it "invokes the linters via bundle exec, not a bare global command" do
      expect(File.read(root.join("lib/tasks/markdown_lint.rake"))).to include("bundle exec mdl"),
        "markdown:check must run the pinned local mdl via bundle exec, not a bare global `mdl`"
      expect(File.read(root.join("lib/tasks/erb_lint.rake"))).to include("bundle exec erb_lint"),
        "erb:check must run the pinned local erb_lint via bundle exec, not a bare global `erb_lint`"
    end

    it "ships no leftover Node toolchain (package.json, lockfile, or .tool-versions entry)" do
      %w[package.json package-lock.json].each do |file|
        expect(File.exist?(root.join(file))).to be(false),
          "expected #{file} to be absent — lint tooling is Ruby-gem-based now, a leftover Node " \
          "manifest would re-invite the drift/toolchain-duplication this describe block guards against"
      end
      tool_versions = File.read(root.join(".tool-versions"))
      expect(tool_versions).not_to match(/^node\b/),
        "expected no `node` line in .tool-versions — nothing in the template needs Node anymore"
    end

    it "does not force brakeman to the latest released version (same drift anti-pattern)" do
      # Active code only — an explanatory comment naming the removed flag is fine.
      active = File.read(root.join("bin/brakeman")).lines.reject { |line| line.strip.start_with?("#") }.join
      expect(active).not_to include("--ensure-latest"),
        "bin/brakeman --ensure-latest fails CI the moment a newer brakeman ships, on every branch with no code change — " \
        "bump deliberately instead (see #299; the drift it caused is PR #319)"
    end
  end
end
