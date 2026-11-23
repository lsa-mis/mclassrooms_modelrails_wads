require "rails_helper"
require "tmpdir"

# `load` defines the class without running it (the $PROGRAM_NAME guard at the
# bottom of the script), matching spec/bin/parallel_rspec_spec.rb. That guard is
# itself asserted in spec/code_smells/template_invariants_spec.rb, because
# without it this very line would run bin/fork against the developer's checkout.
load Rails.root.join("bin/fork")

# Git is exercised for real, never stubbed. Every risk in this script lives in
# the resulting repository state, so `git remote get-url --push upstream` is the
# only assertion that means anything — stubbing `system` would assert that we
# called a string.
RSpec.describe ForkFlow do
  # #789 — `git -C <dir>` LOSES to an inherited GIT_DIR: with one set,
  # `git -C x init` re-initialises $GIT_DIR — flipping core.bare when $GIT_DIR
  # is a worktree gitdir — and `git -C x config` writes $GIT_DIR/config, which
  # for a linked worktree is the SHARED repository config. Git hooks export
  # GIT_DIR (man 5 githooks) and this suite runs under Lefthook, so the
  # fixture's own writes landed in the developer's repository. A nil value
  # deletes the key in the child, restoring `-C` precedence.
  #
  # ForkFlow::CLEAN_GIT_ENV rather than a second copy: the fixture and the script
  # under test must clear the same set, and a constant defined in this describe
  # block would land on Object and collide with template_invariants_spec.rb's.

  let(:workdir) { Pathname.new(Dir.mktmpdir) }
  let(:repo) { workdir.join("my_app") }
  # Must end in modelrails_base or TEMPLATE_REMOTE won't match and every remote
  # example passes vacuously against the "no template remote" branch.
  let(:template_bare) { workdir.join("modelrails_base.git") }

  # rm_rf, not remove_entry: remove_entry raises on a file that vanishes
  # mid-walk, which is exactly what git's background maintenance does to its own
  # lock files. Belt-and-braces with the gc config below.
  after { FileUtils.rm_rf(workdir) }

  def git(*args, dir: repo)
    # -c user.* so commits work on a machine (or CI runner) with no global git
    # identity configured.
    system(ForkFlow::CLEAN_GIT_ENV,
           "git", "-C", dir.to_s, "-c", "user.email=t@example.com", "-c", "user.name=T",
           *args, out: File::NULL, err: File::NULL) || raise("git #{args.join(' ')} failed")
  end

  def capture_git(*args, dir: repo)
    IO.popen(ForkFlow::CLEAN_GIT_ENV, [ "git", "-C", dir.to_s, *args ], err: File::NULL, &:read).to_s.strip
  end

  # Minimal skeleton rather than a copy of the real template: copying would
  # couple this spec to unrelated template edits. The real files are guarded by
  # template invariants instead.
  def write_skeleton
    {
      # .env is gitignored in the real template; without this the fixture's own
      # .env writes would dirty the tree and trip the preflight.
      ".gitignore" => ".env\n",
      "CHANGELOG.md" => "# Changelog\n\n## [Unreleased]\n\n### Fixed\n\n- A template fix.\n\n## v2026.10.27\n\n- Template history.\n",
      "config/application.rb" => "module ModelrailsBase\n  class Application < Rails::Application\n  end\nend\n",
      "config/deploy.yml" => "service: modelrails_base\nimage: you/modelrails_base\n",
      "config/deploy.staging.yml" => "volumes:\n  - \"modelrails_base_staging_storage:/rails/storage\"\n",
      "config/locales/en/brand.en.yml" => %(en:\n  application:\n    name: "ModelRails"\n),
      "config/locales/en/pages.en.yml" => %(en:\n  pages:\n    brand: "ModelRails"\n    address: "support@example.com"\n),
      "public/manifest.webmanifest" => %({"name": "ModelRails"}\n),
      ".github/workflows/docker_build.yml" => "jobs:\n  build:\n    image: modelrails_base:latest\n",
      ".github/workflows/image_scan.yml" => "jobs:\n  scan:\n    image: modelrails_base:latest\n",
      ".github/workflows/hotcell_image_scan.yml" => "jobs:\n  scan:\n    image: modelrails_base-hotcell:scan\n",
      "Dockerfile" => "# docker build -t modelrails_base .\n# docker run -d --name modelrails_base modelrails_base\nFROM ruby\n"
    }.each do |path, content|
      full = repo.join(path)
      FileUtils.mkdir_p(full.dirname)
      full.write(content)
    end
  end

  def build_template_clone
    system(ForkFlow::CLEAN_GIT_ENV, "git", "init", "--bare", "-q", template_bare.to_s) ||
      raise("bare init failed")
    FileUtils.mkdir_p(repo)
    git("init", "-q", "-b", "main")
    # bin/fork makes its OWN commits, which do not inherit the `-c user.*` the
    # helper above passes. A CI runner has no global identity, so without a
    # local one those commits fail — the exact way this suite went red on CI
    # while passing on a laptop that derives an identity from the OS account.
    # useConfigOnly keeps the fixture strict so it can never silently depend on
    # the developer's machine again.
    git("config", "user.useConfigOnly", "true")
    git("config", "user.email", "fixture@example.com")
    git("config", "user.name", "Fixture")
    # Git otherwise spawns background gc/maintenance in these throwaway repos.
    # Under the parallel suite that races the after-hook cleanup, which then
    # fails on a lock file that git deleted mid-walk — an intermittent failure
    # attributed to whichever example happened to be running.
    git("config", "gc.auto", "0")
    git("config", "maintenance.auto", "false")
    write_skeleton
    git("remote", "add", "origin", template_bare.to_s)
    git("add", "-A")
    git("commit", "-qm", "template")
  end

  let(:printed) { StringIO.new }

  # bin/fork runs without the app loaded, so the app's own module must not count as taken here,
  # or a fork named my_app aborts every example that forks a sample my_app.
  before do
    allow(Object).to receive(:const_defined?).and_wrap_original do |original, name, *rest|
      name.to_s != Rails.application.class.module_parent_name && original.call(name, *rest)
    end
  end

  def terminal(typed = "") = StringIO.new(typed).tap { |io| io.define_singleton_method(:tty?) { true } }

  def run_fork(opts = {}, input = StringIO.new)
    flow = described_class.new(opts, root: repo.to_s, input:, output: printed)
    yield flow if block_given?
    silence_stdio { flow.run }
    flow
  end

  def next_steps = printed.string[/== Next steps ==.*/m] || raise("bin/fork printed no Next steps")

  let(:bin_dir) { workdir.join("bin") }
  let(:gh_log) { workdir.join("gh.log") }

  def with_path(*dirs)
    original = ENV["PATH"]
    ENV["PATH"] = dirs.join(":")
    yield
  ensure
    ENV["PATH"] = original
  end

  let(:gh_defaults) do
    {
      "auth status" => "exit 0",
      "api user --jq .login" => "echo me",
      "api user --jq .plan.name" => "echo pro",
      "config get git_protocol -h github.com" => "echo ssh"
    }
  end

  # A fake gh that logs every call and answers by pattern; earlier patterns win.
  def install_fake_gh(cases = {})
    bin_dir.mkpath
    arms = cases.merge(gh_defaults) { |_, given, _| given }.map { |pattern, body| "  #{pattern.gsub(" ", "\\ ")}) #{body} ;;" }
    gh = bin_dir.join("gh")
    gh.write("#!/bin/sh\necho \"$*\" >> #{gh_log}\ncase \"$*\" in\n#{arms.join("\n")}\nesac\n")
    gh.chmod(0o755)
  end

  def gh_calls = gh_log.exist? ? gh_log.readlines(chomp: true) : []

  def with_fake_gh(&) = with_path(bin_dir.to_s, ENV["PATH"], &)

  # Git subprocesses write to fd 1 directly, past the injected output.
  def silence_stdio
    original = STDOUT.dup
    STDOUT.reopen(File::NULL)
    yield
  ensure
    STDOUT.reopen(original)
    original.close
  end

  before { build_template_clone }

  before { allow(Kernel).to receive(:exec).and_raise("bin/fork tried to exec, which would replace the rspec worker") }

  before do
    allow(DevPort).to receive_messages(busy?: false, container?: false)
    allow(Codespaces).to receive(:active?).and_return(false)
  end

  # Read back inside the example, before the after-hook rm_rf deletes workdir,
  # so the #789 guard below can tell "the decoy was written" apart from "the
  # clone helper never got as far as configuring the fixture".
  before { @fixture_user_name = capture_git("config", "--local", "--get", "user.name") }

  # #789 — every git call in this file and in bin/fork is `-C`-scoped, and `-C`
  # loses to an inherited GIT_DIR. Under Lefthook the suite runs inside a hook
  # process, and hooks export GIT_DIR; from a linked worktree that value is
  # absolute, so `git config` at local scope wrote the developer's REAL shared
  # .git/config. This points GIT_DIR at a throwaway decoy for the whole example:
  # if any spawn still honours it, the decoy's config changes and this fails.
  #
  # The snapshot has to be taken HERE, between the assignment and example.run —
  # `before { build_template_clone }` runs inside example.run, so a snapshot in
  # the example body would compare post-damage to post-damage and pass on every
  # seed.
  around do |example|
    decoy = Dir.mktmpdir("fork-spec-git-dir-decoy")
    original_git_dir = ENV["GIT_DIR"]
    git_dir_set = false

    # `begin` opens here, not after the setup: a raise from the containment
    # check, the decoy init or the snapshot read would otherwise leak the
    # mktmpdir. The env restore stays conditional on having actually set it.
    begin
      # realpath on BOTH sides: on macOS Dir.tmpdir is /var/... symlinked to
      # /private/var/..., and a naive start_with? fails open on exactly the
      # platform this repo is developed on.
      tmp_root = Pathname.new(Dir.tmpdir).realpath.to_s
      unless Pathname.new(decoy).realpath.to_s.start_with?(tmp_root)
        raise "refusing to point GIT_DIR at #{decoy} — not under #{tmp_root}"
      end

      # Cleared here too: an ambient GIT_DIR is exactly the condition this
      # guard exists for, and creating the decoy under one would re-initialise
      # the developer's own repository instead.
      system(ForkFlow::CLEAN_GIT_ENV, "git", "init", "-q", decoy, out: File::NULL, err: File::NULL) ||
        raise("decoy init failed")
      decoy_git = File.join(decoy, ".git")
      decoy_config = File.join(decoy_git, "config")
      decoy_before = File.read(decoy_config)

      ENV["GIT_DIR"] = decoy_git
      git_dir_set = true

      example.run

      expect(File.read(decoy_config)).to eq(decoy_before),
        "GIT_DIR decoy repository was written: a git spawn in this file or in " \
        "bin/fork honoured the inherited GIT_DIR instead of its own -C scope. " \
        "In real use that GIT_DIR is the developer's own repository (#789)."
      expect(@fixture_user_name).to eq("Fixture"),
        "the fixture repo never received its local git identity, so the guard " \
        "above proved nothing — the git spawns went somewhere else (#789)."
    ensure
      # ENV["X"] = nil deletes the key, which is the right restore when GIT_DIR
      # was unset. `ensure`, not trust in example.run: the restore has to
      # survive this hook's own raise and a SIGINT.
      ENV["GIT_DIR"] = original_git_dir if git_dir_set
      FileUtils.rm_rf(decoy)
    end
  end

  # #789 canary — the guard above proves no spawn honours an inherited GIT_DIR;
  # this watches the outcome directly, on the very file that was corrupted.
  #
  # --path-format=absolute because --git-common-dir is RELATIVE in a main
  # checkout and would otherwise resolve against the worker's CWD. In a linked
  # worktree it resolves to the MAIN checkout's .git — which is exactly the
  # shared config `git config` at local scope writes, and exactly what #789 lost.
  #
  # Scoped to the keys this leak writes, and to --local, rather than the whole
  # config: under Lefthook the window between the two hooks is minutes long, and
  # a developer running `git config` in another terminal must not turn this red
  # on innocent input. parallel_tests groups whole files, so one worker owns this
  # file and the canary never races itself.
  def checkout_config_canary
    common_dir = IO.popen(
      ForkFlow::CLEAN_GIT_ENV,
      [ "git", "-C", Rails.root.to_s, "rev-parse", "--path-format=absolute", "--git-common-dir" ],
      err: File::NULL, &:read
    ).to_s.strip
    return "(not a git checkout)" if common_dir.empty?

    IO.popen(
      ForkFlow::CLEAN_GIT_ENV,
      [ "git", "--git-dir=#{common_dir}", "config", "--local", "--get-regexp",
        '^(user\.|core\.bare|gc\.auto|maintenance\.auto|remote\.)' ],
      err: File::NULL, &:read
    ).to_s
  end

  before(:context) { @canary_before = checkout_config_canary }

  after(:context) do
    expect(checkout_config_canary).to eq(@canary_before),
      "this spec file changed the git config of the checkout it was running in " \
      "(#789). A git spawn escaped its -C scope — most likely an inherited " \
      "GIT_DIR that some new call site does not clear."
  end

  # -------------------------------------------------------------- name safety

  describe "name validation" do
    # A name reaches config/application.rb as a module declaration. The default
    # is the directory name, so `git clone … 5by5 && bin/fork` gets here with no
    # flags — and the result is a committed app that cannot parse.
    it "refuses a name that cannot begin a Ruby constant" do
      expect { run_fork(name: "5by5", yes: true) }.to raise_error(SystemExit)
    end

    it "refuses a name whose module would reopen a Ruby core class" do
      expect { run_fork(name: "data", yes: true) }.to raise_error(SystemExit)
    end

    # bin/fork is stdlib-only, so Rails and friends are NOT defined in its
    # process — Object.const_defined? cannot see them. Without an explicit
    # denylist, `bin/fork --name rails` writes `module Rails` into
    # config/application.rb and reopens the framework.
    #
    # NOTE: the behavioural examples below cannot prove this on their own —
    # RSpec HAS loaded Rails, so Object.const_defined?("Rails") is true here and
    # they would pass even with no denylist at all. The data assertion is what
    # actually pins the guarantee for the stdlib-only CLI.
    it "denies framework constants a stdlib-only process cannot see" do
      expect(ForkFlow::RESERVED_CONSTANTS)
        .to include("Rails", "ActiveRecord", "ActiveSupport", "ActionController")
    end

    %w[rails active_record action_controller active_support].each do |framework|
      it "refuses #{framework.inspect}, whose module would collide with the framework" do
        expect { run_fork(name: framework, yes: true) }.to raise_error(SystemExit)
      end
    end

    # "café" → "caf" is a surprising thing to discover in your module name and
    # your Kamal service name months later.
    it "refuses a name whose non-ASCII characters would be silently dropped" do
      expect { run_fork(name: "café", yes: true) }.to raise_error(SystemExit)
    end

    it "refuses a name that reduces to nothing" do
      expect { run_fork(name: "___", yes: true) }.to raise_error(SystemExit)
    end

    it "refuses the template's own name" do
      expect { run_fork(name: "modelrails_base", yes: true) }.to raise_error(SystemExit)
    end

    it "accepts a name whose module only the app running this suite defines, as bin/fork's own process does" do
      stub_const("SampleHost", Module.new)
      allow(Rails.application.class).to receive(:module_parent_name).and_return("SampleHost")

      expect { run_fork(name: "sample_host", yes: true) }.not_to raise_error
      expect(repo.join("config/application.rb").read).to include("module SampleHost")
    end

    it "normalizes punctuation and case into a snake_case name" do
      run_fork(name: "My-Great App!", yes: true)

      expect(repo.join("config/application.rb").read).to include("module MyGreatApp")
    end

    # The outcome-level assertion behind the unit checks above: whatever the
    # name derivation produces, the file it lands in must still be Ruby.
    it "leaves config/application.rb parseable as Ruby" do
      run_fork(name: "my_app", yes: true)

      expect { RubyVM::AbstractSyntaxTree.parse(repo.join("config/application.rb").read) }
        .not_to raise_error
    end
  end

  # ------------------------------------------------------------------ presets

  describe "preset validation" do
    it "refuses a preset the app would not boot on" do
      expect { run_fork(name: "my_app", preset: "open_saas", yes: true) }.to raise_error(SystemExit)
    end

    it "writes the preset to .env" do
      run_fork(name: "my_app", preset: "none", yes: true)

      expect(repo.join(".env").read).to include("WORKSPACE_ON_SIGNUP=none")
    end

    # config/initializers/tenancy.rb raises at boot when :shared has no slug, so
    # writing the preset alone hands back a .env the app refuses to start on.
    it "writes the required slug alongside the shared preset" do
      run_fork(name: "my_app", preset: "shared", yes: true)

      env = repo.join(".env").read
      expect(env).to include("WORKSPACE_ON_SIGNUP=shared")
      expect(env).to include("TENANCY_SHARED_WORKSPACE_SLUG=my_app")
    end

    it "says production reads the preset from .fork.yml, not from a variable to set by hand" do
      run_fork(name: "my_app", preset: "shared", yes: true)

      expect(printed.string).to include("production reads the preset from .fork.yml")
      expect(printed.string).not_to include("production env")
    end
  end

  describe ".env handling" do
    it "preserves unrelated variables verbatim" do
      repo.join(".env").write("SECRET_KEY=keep-me\nOTHER=also-keep\n")

      run_fork(name: "my_app", preset: "none", yes: true)

      env = repo.join(".env").read
      expect(env).to include("SECRET_KEY=keep-me")
      expect(env).to include("OTHER=also-keep")
    end

    it "replaces rather than duplicates an existing preset line" do
      repo.join(".env").write("WORKSPACE_ON_SIGNUP=personal\n")

      run_fork(name: "my_app", preset: "none", yes: true)

      expect(repo.join(".env").read.scan(/^WORKSPACE_ON_SIGNUP=/).size).to eq(1)
    end

    it "appends cleanly to a file with no trailing newline" do
      repo.join(".env").write("SECRET_KEY=keep-me")

      run_fork(name: "my_app", preset: "none", yes: true)

      expect(repo.join(".env").read).to include("SECRET_KEY=keep-me\nWORKSPACE_ON_SIGNUP=none")
    end
  end

  # ----------------------------------------------------------- identity rename

  describe "identity rename" do
    it "rewrites every rename target" do
      run_fork(name: "my_app", yes: true)

      expect(repo.join("config/application.rb").read).to include("module MyApp")
      expect(repo.join("config/deploy.yml").read).not_to include("modelrails_base")
      expect(repo.join("config/deploy.staging.yml").read).to include("my_app_staging_storage")
      expect(repo.join("config/locales/en/brand.en.yml").read).to include("My App")
      expect(repo.join("public/manifest.webmanifest").read).to include("My App")
      expect(repo.join(".github/workflows/docker_build.yml").read).to include("my_app:")
      expect(repo.join(".github/workflows/hotcell_image_scan.yml").read).to include("my_app-hotcell:")
      expect(repo.join("Dockerfile").read).to include("docker build -t my_app .").and include("--name my_app my_app")
    end

    it "replaces the template support address with an unmistakable placeholder" do
      flow = run_fork(name: "my_app", yes: true)

      pages = repo.join("config/locales/en/pages.en.yml").read
      expect(pages).not_to include("support@example.com")
      expect(pages).to include("support@my_app.example")
      expect(flow.todos.join).to include("CI fails until")
    end

    it "writes the given support address into the rename commit" do
      run_fork(name: "my_app", support_email: "help@my-app.com", yes: true)

      pages = capture_git("show", "HEAD:config/locales/en/pages.en.yml")
      expect(pages).to include("help@my-app.com")
      expect(pages).not_to include(".example")
      expect(next_steps).not_to include("support address")
    end

    it "refuses a placeholder-shaped support address before changing anything" do
      [ "help@x.example", "help@example.com", "nope" ].each do |address|
        expect { run_fork(name: "my_app", support_email: address, yes: true) }.to raise_error(SystemExit)
        expect(capture_git("log", "--oneline").lines.size).to eq(1)
      end
    end

    it "protects the branches after main reaches GitHub, since the rules then refuse a direct push" do
      flow = run_fork(name: "my_app", yes: true)

      push = flow.todos.index { |t| t.include?("git push") }
      rules = flow.todos.index { |t| t.include?("bin/branch-rules") }
      expect(rules).to be > push
    end

    # CI's comment gate reads a fork's first PR, so the rename commit has to pass it.
    it "writes a .fork.yml header the comment gate accepts" do
      run_fork(name: "my_app", preset: "none", yes: true)

      expect(repo.join(".fork.yml").readlines.take_while { |line| line.start_with?("#") }.size).to be <= 2
    end

    it "records provenance that round-trips through safe YAML" do
      run_fork(name: "my_app", preset: "none", yes: true)

      config = YAML.safe_load_file(repo.join(".fork.yml"))
      expect(config).to include("name" => "my_app", "product_name" => "My App", "preset" => "none")
      expect(config["template_baseline"]).to match(/\A[0-9a-f]{40}\z/)
    end

    it "doesn't ask a fork developer to tag the template" do
      run_fork(name: "my_app", preset: "none", yes: true)

      expect(next_steps).not_to include("forks/")
    end

    it "doesn't assume main is the branch that reaches GitHub" do
      run_fork(name: "my_app", preset: "none", yes: true)

      expect(next_steps).not_to include("Once main is on GitHub")
    end

    it "starts the fork's changelog clean, in the rename commit: the template's releases aren't the fork's" do
      run_fork(name: "my_app", yes: true)

      expect(repo.join("CHANGELOG.md").read)
        .to eq("# Changelog\n\nAll notable changes to My App are documented here.\n\n## [Unreleased]\n")
      expect(capture_git("show", "--name-only", "--pretty=", "HEAD")).to include("CHANGELOG.md")
    end

    it "commits the rename as one findable commit" do
      run_fork(name: "my_app", yes: true)

      expect(capture_git("log", "-1", "--pretty=%s")).to eq("Rename identity: My App")
    end

    # A fork that deleted a rename target (plenty won't use Kamal) must fail
    # with a sentence BEFORE the remote surgery, not an Errno mid-flight.
    it "aborts before touching remotes when a rename target is missing" do
      repo.join("config/deploy.yml").delete

      expect { run_fork(name: "my_app", yes: true) }.to raise_error(SystemExit)
      expect(capture_git("remote")).to eq("origin")
    end
  end

  # ------------------------------------------------------------ remote surgery

  describe "remote surgery" do
    it "converts the template origin into a push-disabled upstream" do
      run_fork(name: "my_app", yes: true)

      expect(capture_git("remote", "get-url", "upstream")).to eq(template_bare.to_s)
      expect(capture_git("remote", "get-url", "--push", "upstream")).to eq("DISABLED")
    end

    # `git remote rename` repoints branch.<name>.remote, so until an origin
    # exists a plain `git pull` would merge the TEMPLATE into the fork's work.
    it "stops the branch tracking the template" do
      run_fork(name: "my_app", yes: true)

      expect(capture_git("rev-parse", "--abbrev-ref", "@{u}")).to be_empty
    end

    it "adds the given origin" do
      run_fork(name: "my_app", origin: "git@github.com:me/my_app.git", yes: true)

      expect(capture_git("remote", "get-url", "origin")).to eq("git@github.com:me/my_app.git")
    end

    it "makes the given origin gh's default, since gh would otherwise pick upstream: the template" do
      run_fork(name: "my_app", origin: "git@github.com:me/my_app.git", yes: true)

      expect(capture_git("config", "--get", "remote.origin.gh-resolved")).to eq("base")
      expect(capture_git("config", "--get", "remote.pushDefault")).to eq("origin")
    end

    it "makes an origin that was already there gh's default too" do
      git("remote", "set-url", "origin", "git@github.com:me/my_app.git")
      run_fork(name: "my_app", yes: true)

      expect(capture_git("config", "--get", "remote.origin.gh-resolved")).to eq("base")
      expect(capture_git("config", "--get", "remote.pushDefault")).to eq("origin")
    end

    # Anchoring matters: an unanchored pattern matches "me/not_modelrails_base",
    # which would disconnect a user's own repository.
    # A half-configured repo (someone followed the guide partway, or an earlier
    # run died) must be diagnosed BEFORE the first mutation — `remote rename`
    # would fail on the existing name, leaving origin's push URL already
    # disabled and the user stranded mid-surgery.
    it "aborts without mutating when an unexpected upstream already exists" do
      git("remote", "add", "upstream", template_bare.to_s)

      expect { run_fork(name: "my_app", yes: true) }.to raise_error(SystemExit)
      expect(capture_git("remote", "get-url", "--push", "origin")).to eq(template_bare.to_s)
    end

    it "leaves a non-template origin alone" do
      git("remote", "set-url", "origin", "git@github.com:me/not_modelrails_base.git")

      run_fork(name: "my_app", yes: true)

      expect(capture_git("remote", "get-url", "origin")).to eq("git@github.com:me/not_modelrails_base.git")
      expect(capture_git("remote")).not_to include("upstream")
    end
  end

  describe "starting from the template's latest release" do
    def commit_file(path, content, message)
      repo.join(path).write(content)
      git("add", path)
      git("commit", "-qm", message)
    end

    def release_on_main(tag)
      commit_file("release.txt", "#{tag}\n", "Release #{tag}")
      git("tag", tag)
    end

    def clone_next(unreleased: true)
      git("push", "-q", "origin", "main", "--tags")
      git("switch", "-q", "-c", "next")
      commit_file("unreleased.txt", "next only\n", "Unreleased work") if unreleased
      git("push", "-q", "-u", "origin", "next")
    end

    def commit_of(ref) = capture_git("rev-parse", "#{ref}^{commit}")
    def fork_file = YAML.safe_load_file(repo.join(".fork.yml"))

    it "moves next to the newest release on main, then renames on top of it" do
      %w[v2026.11.11 v2026.11.13-2 v2026.11.13-10].each { |tag| release_on_main(tag) }
      clone_next

      run_fork(name: "my_app", yes: true)

      expect(capture_git("rev-parse", "HEAD~1")).to eq(commit_of("v2026.11.13-10"))
      expect(repo.join("unreleased.txt")).not_to exist
    end

    it "records the release and its commit in .fork.yml" do
      release_on_main("v2026.11.13")
      clone_next

      run_fork(name: "my_app", yes: true)

      expect(fork_file).to include("template_release" => "v2026.11.13", "template_baseline" => commit_of("v2026.11.13"))
    end

    it "ignores a v tag that main can't reach" do
      release_on_main("v2026.11.13")
      clone_next
      git("tag", "v2026.11.20")
      git("push", "-q", "origin", "--tags")

      run_fork(name: "my_app", yes: true)

      expect(fork_file["template_release"]).to eq("v2026.11.13")
    end

    it "says so when next is already at the release" do
      release_on_main("v2026.11.13")
      clone_next(unreleased: false)

      run_fork(name: "my_app", yes: true)

      expect(printed.string).to include("next is already at the template's release v2026.11.13")
      expect(capture_git("rev-parse", "HEAD~1")).to eq(commit_of("v2026.11.13"))
    end

    it "keeps next as cloned under --from-next" do
      release_on_main("v2026.11.13")
      clone_next

      run_fork(name: "my_app", from_next: true, yes: true)

      expect(repo.join("unreleased.txt")).to exist
      expect(fork_file).not_to have_key("template_release")
    end

    it "refuses, before the remote surgery, when next has commits the template doesn't" do
      release_on_main("v2026.11.13")
      clone_next
      commit_file("mine.txt", "local\n", "My own work")
      before_head = capture_git("rev-parse", "HEAD")

      expect { run_fork(name: "my_app", yes: true) }.to raise_error(SystemExit)
      expect(capture_git("rev-parse", "HEAD")).to eq(before_head)
      expect(capture_git("remote")).to eq("origin")
    end

    it "starts from next as cloned, and says so, when main has no release" do
      clone_next

      run_fork(name: "my_app", yes: true)

      expect(repo.join("unreleased.txt")).to exist
      expect(printed.string).to include("no release tag on origin/main")
    end

    it "uses the releases the clone already knows when the template can't be reached" do
      release_on_main("v2026.11.13")
      clone_next
      git("remote", "set-url", "origin", workdir.join("gone/modelrails_base.git").to_s)

      run_fork(name: "my_app", yes: true)

      expect(fork_file["template_release"]).to eq("v2026.11.13")
      expect(printed.string).to include("couldn't reach origin")
    end

    it "leaves next alone when origin is the fork's own repository" do
      release_on_main("v2026.11.13")
      clone_next
      git("remote", "set-url", "origin", workdir.join("my_own_app.git").to_s)

      run_fork(name: "my_app", yes: true)

      expect(repo.join("unreleased.txt")).to exist
    end

    it "plans the move without making it under --dry-run" do
      release_on_main("v2026.11.13")
      clone_next
      before_head = capture_git("rev-parse", "HEAD")

      run_fork(name: "my_app", dry_run: true, yes: true)

      expect(capture_git("rev-parse", "HEAD")).to eq(before_head)
      expect(printed.string).to include("would: move next to the template's latest release v2026.11.13")
    end
  end

  # A synced mirror of the template (acme/modelrails_base_mirror) is the
  # template under another name, so TEMPLATE_REMOTE cannot know it. --template
  # names it explicitly; the match is URL equality, never a looser pattern, so
  # the anchoring guarantee above ("me/not_modelrails_base" is left alone) holds.
  describe "--template (a mirror of the template under another name)" do
    let(:mirror_bare) { workdir.join("modelrails_base_mirror.git") }

    before do
      system(ForkFlow::CLEAN_GIT_ENV, "git", "init", "--bare", "-q", mirror_bare.to_s) ||
        raise("mirror bare init failed")
    end

    # The GitHub Fork button path: origin is already the product, no upstream
    # yet. bin/fork records the URL; bin/setup adds the remote in every clone.
    it "records the template url in .fork.yml when nothing but origin exists" do
      git("remote", "set-url", "origin", "git@github.com:me/my_app.git")

      run_fork(name: "my_app", template: mirror_bare.to_s, yes: true)

      expect(YAML.safe_load_file(repo.join(".fork.yml"))["template_url"]).to eq(mirror_bare.to_s)
      expect(capture_git("remote")).not_to include("upstream")
    end

    # The clone-the-template path, with the mirror as origin. Equality is
    # .git-insensitive: the remote has the suffix, the flag does not.
    it "converts an origin equal to --template into a push-disabled upstream" do
      git("remote", "set-url", "origin", mirror_bare.to_s)

      run_fork(name: "my_app", template: mirror_bare.to_s.delete_suffix(".git"),
               origin: "git@github.com:me/my_app.git", yes: true)

      expect(capture_git("remote", "get-url", "upstream")).to eq(mirror_bare.to_s)
      expect(capture_git("remote", "get-url", "--push", "upstream")).to eq("DISABLED")
      expect(capture_git("remote", "get-url", "origin")).to eq("git@github.com:me/my_app.git")
    end

    it "treats an upstream equal to --template as already configured" do
      git("remote", "set-url", "origin", "git@github.com:me/my_app.git")
      git("remote", "add", "upstream", mirror_bare.to_s)
      git("remote", "set-url", "--push", "upstream", "DISABLED")

      run_fork(name: "my_app", template: mirror_bare.to_s, yes: true)

      expect(YAML.safe_load_file(repo.join(".fork.yml"))["template_url"]).to eq(mirror_bare.to_s)
      expect(capture_git("remote", "get-url", "upstream")).to eq(mirror_bare.to_s)
    end

    # Negative control for the design choice: without the flag, a name that
    # merely starts with the template's is still nobody's template.
    it "leaves a suffix-named origin alone when no --template is given" do
      git("remote", "set-url", "origin", "git@github.com:me/modelrails_base_myapp.git")

      run_fork(name: "my_app", yes: true)

      expect(capture_git("remote", "get-url", "origin")).to eq("git@github.com:me/modelrails_base_myapp.git")
      expect(capture_git("remote")).not_to include("upstream")
    end
  end

  # Git carries no record of what a fork was forked from; GitHub does. When
  # nothing names the template, bin/fork asks `gh` for origin's parent. The
  # fake gh below answers only for the repo it is asked about, so a wrong
  # owner/repo parse reads as "GitHub has no parent", not as a pass.
  describe "deriving the template from GitHub" do
    let(:parent_url) { "git@github.com:org/modelrails_base_mirror.git" }

    def install_parent_gh = install_fake_gh("*repos/me/my_app*" => %(echo "#{parent_url}"))

    def fork_config
      YAML.safe_load_file(repo.join(".fork.yml"))
    end

    before { git("remote", "set-url", "origin", "git@github.com:me/my_app.git") }

    it "records origin's GitHub parent as the template when gh can answer" do
      install_parent_gh

      with_path(bin_dir.to_s, ENV["PATH"]) { run_fork(name: "my_app", yes: true) }

      expect(fork_config["template_url"]).to eq(parent_url)
      expect(capture_git("remote")).not_to include("upstream")
    end

    it "suggests leaving the fork network when the template came from origin's GitHub parent" do
      install_parent_gh

      flow = with_path(bin_dir.to_s, ENV["PATH"]) { run_fork(name: "my_app", yes: true) }

      expect(flow.todos.join).to include("Leave fork network")
    end

    it "warns that a Fork-button repository starts from next and points to the clone path" do
      install_parent_gh

      with_path(bin_dir.to_s, ENV["PATH"]) { run_fork(name: "my_app", yes: true) }

      expect(printed.string).to include("origin is a GitHub fork")
      expect(printed.string).to include("starts from next, not the latest release")
      expect(printed.string).to include("/docs/developer/forking#start-a-new-app")
    end

    it "does not call origin a GitHub fork when GitHub reports no parent" do
      install_parent_gh
      git("remote", "set-url", "origin", "git@github.com:me/plain_repo.git")

      with_path(bin_dir.to_s, ENV["PATH"]) { run_fork(name: "my_app", yes: true) }

      expect(printed.string).not_to include("origin is a GitHub fork")
    end

    it "prefers an explicit --template over GitHub's answer" do
      install_parent_gh

      with_path(bin_dir.to_s, ENV["PATH"]) { run_fork(name: "my_app", template: "git@github.com:org/other.git", yes: true) }

      expect(fork_config["template_url"]).to eq("git@github.com:org/other.git")
    end

    it "records no template when GitHub reports no parent" do
      install_parent_gh
      git("remote", "set-url", "origin", "git@github.com:me/plain_repo.git")

      with_path(bin_dir.to_s, ENV["PATH"]) { run_fork(name: "my_app", yes: true) }

      expect(fork_config).not_to have_key("template_url")
    end

    # On the clone path origin IS the template, so its GitHub parent is the
    # template's own parent — recording that would point upstream one hop too
    # far. --origin is the signal for that path; --template names the mirror.
    it "does not ask GitHub on the clone path (--origin given)" do
      install_parent_gh

      with_path(bin_dir.to_s, ENV["PATH"]) { run_fork(name: "my_app", origin: "git@github.com:me/other.git", yes: true) }

      expect(fork_config).not_to have_key("template_url")
    end

    it "falls back to verify-by-hand when gh is not installed" do
      # A PATH holding nothing but git: gh is absent the way it is on a machine
      # that never installed it, not faked as failing.
      git_binary = ENV["PATH"].split(":").map { |dir| File.join(dir, "git") }.find { |path| File.executable?(path) }
      bin_dir.mkpath
      bin_dir.join("git").make_symlink(git_binary)

      with_path(bin_dir.to_s) { run_fork(name: "my_app", yes: true) }

      expect(fork_config).not_to have_key("template_url")
      expect(capture_git("remote")).not_to include("upstream")
    end
  end

  # Pushes to git@github.com:me/my_app.git land in a local bare repo through insteadOf.
  shared_context "a GitHub remote" do
    let(:github_remote_bare) { workdir.join("github_me_my_app.git") }

    def remote_next = capture_git("--git-dir", github_remote_bare.to_s, "rev-parse", "--verify", "-q", "next", dir: workdir)

    before do
      git("branch", "-m", "main", "next")
      system(ForkFlow::CLEAN_GIT_ENV, "git", "init", "--bare", "-q", github_remote_bare.to_s) || raise("bare init failed")
      git("config", "url.#{github_remote_bare}.insteadOf", "git@github.com:me/my_app.git")
    end
  end

  describe "creating the GitHub repo" do
    include_context "a GitHub remote"

    it "creates a public repo named after the project, then pushes next to it" do
      install_fake_gh

      with_fake_gh { run_fork(name: "my_app", github: "me", yes: true) }

      expect(gh_calls).to include("repo create me/my_app --public")
      expect(remote_next).to eq(capture_git("rev-parse", "HEAD"))
      expect(capture_git("config", "--get", "remote.origin.url")).to eq("git@github.com:me/my_app.git")
    end

    it "never creates a repo under --yes without --github" do
      install_fake_gh

      with_fake_gh { run_fork(name: "my_app", yes: true) }

      expect(gh_calls.grep(/repo create/)).to be_empty
    end

    it "says how to publish when --yes skipped GitHub" do
      install_fake_gh

      with_fake_gh { run_fork(name: "my_app", yes: true) }

      expect(printed.string).to match(%r{Not published to GitHub.*bin/fork --github OWNER})
    end

    it "stays quiet about publishing under --no-github" do
      run_fork(name: "my_app", github: false, yes: true)

      expect(printed.string).not_to include("Not published")
    end

    it "takes --github OWNER/NAME as the repo name" do
      install_fake_gh
      git("config", "url.#{github_remote_bare}.insteadOf", "git@github.com:org/other.git")

      with_fake_gh { run_fork(name: "my_app", github: "org/other", yes: true) }

      expect(gh_calls).to include("repo create org/other --public")
    end

    it "uses https when gh is set to https" do
      install_fake_gh("config get git_protocol -h github.com" => "echo https", "config get git_protocol" => "echo ssh")
      git("config", "url.#{github_remote_bare}.insteadOf", "https://github.com/me/my_app.git")

      with_fake_gh { run_fork(name: "my_app", github: "me", yes: true) }

      expect(capture_git("config", "--get", "remote.origin.url")).to eq("https://github.com/me/my_app.git")
      expect(remote_next).to eq(capture_git("rev-parse", "HEAD"))
    end

    it "creates nothing and pushes nothing when gh repo create fails, and keeps the rest of the run" do
      install_fake_gh("repo create*" => "echo 'name already exists on this account' >&2; exit 1")

      flow = with_fake_gh { run_fork(name: "my_app", github: "me", yes: true) }

      expect(system(ForkFlow::CLEAN_GIT_ENV, "git", "-C", repo.to_s, "remote", "get-url", "origin", err: File::NULL)).to be(false)
      expect(remote_next).to be_empty
      expect(flow.todos.join).to match(/--origin \S+ --github/)
      expect(flow.make_it_yours.join).to include("Rewrite marketing copy")
    end

    it "finishes with the rerun it advised after a failed create" do
      install_fake_gh("repo create*" => "echo 'name already exists on this account' >&2; exit 1",
                      "api repos/me/my_app/rulesets --jq length" => "echo 0")
      with_fake_gh { run_fork(name: "my_app", github: "me", yes: true) }

      with_fake_gh { run_fork(origin: "git@github.com:me/my_app.git", github: true, yes: true) }

      expect(gh_calls.grep(/repo create/).size).to eq(1)
      expect(capture_git("config", "--get", "remote.origin.url")).to eq("git@github.com:me/my_app.git")
      expect(remote_next).to eq(capture_git("rev-parse", "HEAD"))
    end

    it "refuses a resume that names both an origin and a new repo's owner" do
      install_fake_gh
      with_fake_gh { run_fork(name: "my_app", yes: true) }

      expect { with_fake_gh { run_fork(origin: "git@github.com:me/my_app.git", github: "org", yes: true) } }
        .to raise_error(SystemExit)
      expect(gh_calls.grep(/repo create/)).to be_empty
    end

    it "refuses --github from a branch other than next before renaming anything" do
      install_fake_gh
      git("branch", "-m", "next", "wip")

      expect { with_fake_gh { run_fork(name: "my_app", github: "me", yes: true) } }
        .to raise_error(SystemExit).and output(/git switch next/).to_stderr
      expect(capture_git("log", "--oneline").lines.size).to eq(1)
      expect(gh_calls.grep(/repo create/)).to be_empty
    end

    it "warns about the free plan and creates the private repo without rules under --yes" do
      install_fake_gh("api user --jq .plan.name" => "echo free")

      flow = with_fake_gh { run_fork(name: "my_app", github: "me", visibility: "private", yes: true) }

      expect(gh_calls).to include("repo create me/my_app --private")
      expect(flow.todos.join).to include("free plan").and include("bin/branch-rules")
    end

    it "goes on when the plan can't be read" do
      install_fake_gh("api user --jq .plan.name" => "exit 1")

      with_fake_gh { run_fork(name: "my_app", github: "me", visibility: "private", yes: true) }

      expect(gh_calls).to include("repo create me/my_app --private")
    end

    it "skips GitHub and prints the manual steps when gh is missing" do
      git_binary = ENV["PATH"].split(":").map { |dir| File.join(dir, "git") }.find { |path| File.executable?(path) }
      bin_dir.mkpath
      bin_dir.join("git").make_symlink(git_binary)

      flow = with_path(bin_dir.to_s) { run_fork(name: "my_app", github: "me", yes: true) }

      push = flow.todos.index { |t| t.include?("git push -u origin next") }
      rules = flow.todos.index { |t| t.include?("bin/branch-rules") }
      expect(push).not_to be_nil
      expect(rules).to be > push
    end

    it "asks before creating when interactive, defaulting to yes" do
      install_fake_gh

      with_fake_gh do
        run_fork({ name: "my_app" }, terminal) do |flow|
          allow(flow).to receive(:offer_setup!).and_return(false)
        end
      end

      expect(gh_calls).to include("repo create me/my_app --public")
    end

    it "offers the GitHub step when a forked repo has no origin" do
      install_fake_gh
      with_fake_gh { run_fork(name: "my_app", yes: true) }

      with_fake_gh { run_fork(github: "me", yes: true) }

      expect(gh_calls).to include("repo create me/my_app --public")
      expect(remote_next).to eq(capture_git("rev-parse", "HEAD"))
    end

    it "prints the GitHub steps under --dry-run without running them" do
      install_fake_gh
      with_fake_gh { run_fork(name: "my_app", github: "me", dry_run: true, yes: true) }

      expect(gh_calls.grep(/repo create/)).to be_empty
      expect(printed.string).to match(%r{would: create the GitHub repo me/my_app \(public\)})
    end
  end

  describe "protecting the branches" do
    include_context "a GitHub remote"
    let(:rules_log) { workdir.join("rules.log") }

    def rules_lines = rules_log.exist? ? rules_log.readlines(chomp: true) : []
    def rules_calls = rules_lines.grep_v(%r{refs/heads/next})

    around do |example|
      ENV["FAKE_RULES_LOG"] = rules_log.to_s
      example.run
    ensure
      ENV.delete("FAKE_RULES_LOG")
    end

    # Committed, so the clean-tree preflight still passes; it records what GitHub held when it ran.
    before do
      rules = repo.join("bin/branch-rules")
      rules.dirname.mkpath
      rules.write("#!/bin/sh\necho \"$*\" >> \"$FAKE_RULES_LOG\"\ngit ls-remote origin refs/heads/next >> \"$FAKE_RULES_LOG\"\n")
      rules.chmod(0o755)
      git("add", "bin/branch-rules")
      git("commit", "-qm", "branch rules")
    end

    it "applies solo rules after the push" do
      install_fake_gh

      with_fake_gh { run_fork(name: "my_app", github: "me", yes: true) }

      expect(rules_calls).to eq([ "--solo" ])
      expect(rules_lines.grep(%r{refs/heads/next}).join).to include(capture_git("rev-parse", "HEAD"))
    end

    it "applies team rules with --team" do
      install_fake_gh

      with_fake_gh { run_fork(name: "my_app", github: "me", team: true, yes: true) }

      expect(rules_calls).to eq([ "" ])
    end

    it "pushes next to an existing origin and then protects it, when asked to with --github" do
      install_fake_gh("*repos/me/my_app*" => %(echo "git@github.com:org/modelrails_base_mirror.git"))
      git("remote", "set-url", "origin", "git@github.com:me/my_app.git")

      with_fake_gh { run_fork(name: "my_app", github: true, yes: true) }

      expect(remote_next).to eq(capture_git("rev-parse", "HEAD"))
      expect(rules_calls).to eq([ "--solo" ])
      expect(gh_calls.grep(/repo create/)).to be_empty
    end

    it "pushes the rename over a Fork-button fork's next past the pre-push protected-branch check" do
      install_fake_gh("*repos/me/my_app*" => %(echo "git@github.com:org/modelrails_base_mirror.git"))
      git("push", "-q", github_remote_bare.to_s, "HEAD:refs/heads/next")
      git("remote", "set-url", "origin", "git@github.com:me/my_app.git")
      hook = repo.join(".git/hooks/pre-push")
      hook.write("#!/bin/sh\nexec #{Rails.root.join("bin/protected-branch-check")} \"$1\"\n")
      hook.chmod(0o755)

      with_fake_gh { run_fork(name: "my_app", github: true, yes: true) }

      expect(remote_next).to eq(capture_git("rev-parse", "HEAD"))
      expect(rules_calls).to eq([ "--solo" ])
      expect(next_steps).not_to include("git push")
    end

    it "leaves an existing origin alone under --yes without --github" do
      install_fake_gh
      git("remote", "set-url", "origin", "git@github.com:me/my_app.git")

      flow = with_fake_gh { run_fork(name: "my_app", yes: true) }

      expect(remote_next).to be_empty
      expect(rules_calls).to be_empty
      push = flow.todos.index { |t| t.include?(ForkFlow::PUSH_NEXT) }
      expect(flow.todos.index { |t| t.include?("bin/branch-rules") }).to be > push
    end

    it "says how to push when --yes skipped an existing origin" do
      install_fake_gh
      git("remote", "set-url", "origin", "git@github.com:me/my_app.git")

      with_fake_gh { run_fork(name: "my_app", yes: true) }

      expect(printed.string).to match(%r{Not pushed to origin.*bin/fork --github$})
    end

    it "pushes and protects a forked repo whose origin has no rules yet, on rerun with --github" do
      install_fake_gh("api repos/me/my_app/rulesets --jq length" => "echo 0")
      git("remote", "set-url", "origin", "git@github.com:me/my_app.git")
      with_fake_gh { run_fork(name: "my_app", yes: true) }

      with_fake_gh { run_fork(github: true, yes: true) }

      expect(remote_next).to eq(capture_git("rev-parse", "HEAD"))
      expect(rules_calls).to eq([ "--solo" ])
    end

    it "leaves a forked repo that already has rules alone on rerun" do
      install_fake_gh("api repos/me/my_app/rulesets --jq length" => "echo 3")
      git("remote", "set-url", "origin", "git@github.com:me/my_app.git")
      with_fake_gh { run_fork(name: "my_app", yes: true) }

      with_fake_gh { run_fork(github: true, yes: true) }

      expect(remote_next).to be_empty
      expect(rules_calls).to be_empty
    end

    it "pushes to a repo that already exists with --origin URL --github" do
      install_fake_gh

      with_fake_gh { run_fork(name: "my_app", origin: "git@github.com:me/my_app.git", github: true, yes: true) }

      expect(gh_calls.grep(/repo create/)).to be_empty
      expect(remote_next).to eq(capture_git("rev-parse", "HEAD"))
      expect(rules_calls).to eq([ "--solo" ])
    end

    it "applies no rules when the push is rejected" do
      install_fake_gh
      empty_tree = capture_git("hash-object", "-t", "tree", "/dev/null")
      stray = capture_git("commit-tree", empty_tree, "-m", "someone else's next")
      git("push", "-q", github_remote_bare.to_s, "#{stray}:refs/heads/next")
      git("remote", "set-url", "origin", "git@github.com:me/my_app.git")

      flow = with_fake_gh { run_fork(name: "my_app", github: true, yes: true) }

      expect(rules_calls).to be_empty
      push = flow.todos.index { |t| t.include?(ForkFlow::PUSH_NEXT) }
      expect(flow.todos.index { |t| t.include?("bin/branch-rules") }).to be > push
    end
  end

  # ------------------------------------------------------- resumability claims

  describe "re-running" do
    it "reports an already-forked repo without renaming anything again" do
      run_fork(name: "my_app", yes: true)
      before_head = capture_git("rev-parse", "HEAD")

      run_fork(yes: true)

      expect(capture_git("rev-parse", "HEAD")).to eq(before_head)
    end

    it "sets a real support address on a forked repo still carrying the placeholder" do
      run_fork(name: "my_app", yes: true)

      run_fork(support_email: "help@my-app.com", yes: true)

      expect(capture_git("log", "-1", "--format=%s")).to eq("Set the support address")
      expect(capture_git("show", "--name-only", "--format=", "HEAD")).to eq("config/locales/en/pages.en.yml")
      expect(capture_git("show", "HEAD:config/locales/en/pages.en.yml")).to include("help@my-app.com")
    end

    it "leaves uncommitted edits to pages.en.yml out of the support-address commit" do
      run_fork(name: "my_app", yes: true)
      before_head = capture_git("rev-parse", "HEAD")
      pages = repo.join("config/locales/en/pages.en.yml")
      pages.write(pages.read + "    draft: \"half-written copy\"\n")

      flow = run_fork(support_email: "help@my-app.com", yes: true)

      expect(capture_git("rev-parse", "HEAD")).to eq(before_head)
      expect(pages.read).to include("half-written copy")
      expect(flow.todos.join).to include("support address")
    end

    # The script's headline claim. config/application.rb is the first file
    # written, so deriving "already forked" from the worktree would flip true
    # mid-rename and strand the remaining files forever.
    it "completes a rename that was interrupted partway" do
      run_fork(name: "my_app", yes: true)
      # Simulate an interruption that renamed application.rb but not deploy.yml.
      repo.join("config/deploy.yml").write("service: modelrails_base\n")
      repo.join(".fork.yml").delete
      git("add", "-A")
      git("commit", "-qm", "half-renamed")

      run_fork(name: "my_app", yes: true)

      expect(repo.join("config/deploy.yml").read).not_to include("modelrails_base")
    end

    # The likeliest interruption of all: files written, commit never made (a
    # Ctrl-C, a machine with no git identity, a failing pre-commit hook). The
    # clean-tree preflight must not then refuse the very repair the header
    # promises — "commit or stash first" would have the user stash their own
    # half-finished rename.
    it "completes a rename whose commit never happened" do
      repo.join("config/application.rb").write("module MyApp\nend\n")
      repo.join("config/deploy.yml").write("service: modelrails_base\n")

      expect { run_fork(name: "my_app", yes: true) }.not_to raise_error

      expect(repo.join("config/deploy.yml").read).not_to include("modelrails_base")
      expect(capture_git("status", "--porcelain")).to be_empty
    end

    it "still refuses when the dirty files are the developer's own work" do
      repo.join("app_notes.txt").write("wip")

      expect { run_fork(name: "my_app", yes: true) }.to raise_error(SystemExit)
    end

    it "treats a hand-renamed module without provenance as unfinished" do
      repo.join("config/application.rb").write("module MyApp\nend\n")
      git("add", "-A")
      git("commit", "-qm", "hand rename")

      run_fork(name: "my_app", yes: true)

      expect(repo.join("config/deploy.yml").read).not_to include("modelrails_base")
      expect(repo.join(".fork.yml")).to exist
    end
  end

  describe "preset changes on a forked repo" do
    before { run_fork(name: "my_app", preset: "personal", yes: true) }

    it "records a changed preset" do
      run_fork(preset: "none", yes: true)

      expect(YAML.safe_load_file(repo.join(".fork.yml"))["preset"]).to eq("none")
      expect(repo.join(".env").read).to include("WORKSPACE_ON_SIGNUP=none")
    end

    # The init path is protected by the clean-tree preflight, but a forked repo
    # deliberately skips that check — so this is where an unscoped `git commit`
    # would sweep a developer's staged work (a secret, a scratch file) into a
    # commit they never intended, with no opt-in flag required.
    it "never commits unrelated staged work" do
      repo.join("scratch_notes.txt").write("do-not-commit")
      git("add", "scratch_notes.txt")

      run_fork(preset: "none", yes: true)

      expect(capture_git("show", "--name-only", "--pretty=", "HEAD")).not_to include("scratch_notes.txt")
    end

    # Byte-identical provenance stages nothing, so an unguarded commit aborts.
    it "is a no-op when the preset is unchanged" do
      before_head = capture_git("rev-parse", "HEAD")

      expect { run_fork(preset: "personal", yes: true) }.not_to raise_error
      expect(capture_git("rev-parse", "HEAD")).to eq(before_head)
    end
  end

  # ------------------------------------------------------------- verify sweep

  describe "the verify sweep" do
    it "reports no live tokens after a clean rename" do
      flow = run_fork(name: "my_app", yes: true)

      expect(flow.step_verify![:live]).to be_blank
    end

    it "leaves nothing of the template in the Dockerfile's usage comment" do
      flow = run_fork(name: "my_app", yes: true)

      expect(flow.step_verify!.values.flatten).not_to include("Dockerfile")
    end

    it "flags a live template token left in a fork-owned file" do
      run_fork(name: "my_app", yes: true)
      repo.join("config/deploy.yml").write("service: modelrails_base\n")

      flow = described_class.new({}, root: repo.to_s, output: printed)

      expect(flow.step_verify![:live]).to include("config/deploy.yml")
    end

    # A working-tree grep reports thousands of hits from worktrees and build
    # artifacts, burying the handful that matter. git grep searches tracked
    # files only.
    it "ignores untracked artifacts" do
      run_fork(name: "my_app", yes: true)
      FileUtils.mkdir_p(repo.join("graphify-out"))
      repo.join("graphify-out/graph.json").write(%({"f": "modelrails_base"}))

      flow = described_class.new({}, root: repo.to_s, output: printed)

      expect(flow.step_verify!.values.flatten).not_to include("graphify-out/graph.json")
    end

    # The template documents its own fork seams inside block comments — a CSS
    # /* */ in _brand.css and a multi-line <%# %> in _footer.html.erb. A
    # line-based check can't see those and reports both as rename misses,
    # sending forkers to "fix" prose that is correct.
    it "sees a token inside a CSS block comment" do
      run_fork(name: "my_app", yes: true)
      repo.join("config/deploy.yml").write(<<~CSS)
        /* Brand overrides
           Upstream (modelrails_base) ships this empty.
        */
        service: my_app
      CSS

      flow = described_class.new({}, root: repo.to_s, output: printed)

      expect(flow.step_verify![:live]).to be_blank
    end

    it "sees a token inside a multi-line ERB comment" do
      run_fork(name: "my_app", yes: true)
      repo.join("config/deploy.yml").write(<<~ERB)
        <%# two logo links are never both present, so screen readers
            never encounter two "ModelRails" links at once. %>
        service: my_app
      ERB

      flow = described_class.new({}, root: repo.to_s, output: printed)

      expect(flow.step_verify![:live]).to be_blank
    end

    # modelrails_ui is a gem this app depends on by name forever. Files whose
    # only match is the library name aren't seam docs and shouldn't be listed.
    it "says nothing about files that merely name the modelrails_ui gem" do
      run_fork(name: "my_app", yes: true)
      repo.join("config/deploy.yml").write("service: my_app\n# diverges from modelrails_ui's default\n")

      flow = described_class.new({}, root: repo.to_s, output: printed)

      triage = flow.step_verify!
      expect(triage[:gem_reference]).to include("config/deploy.yml")
      expect(triage[:live] + triage[:comment]).not_to include("config/deploy.yml")
    end

    it "says nothing about files that only use the template's code namespaces" do
      run_fork(name: "my_app", yes: true)
      repo.join(".rubocop.yml").write("require:\n  - ./lib/rubocop/modelrails\nModelRails/NoDefaultScope:\n  Enabled: true\n")
      repo.join("theme.js").write("window.ModelRails = window.ModelRails || {};\nmodule ModelRails\n")
      git("add", ".rubocop.yml", "theme.js")

      flow = described_class.new({}, root: repo.to_s, output: printed)

      triage = flow.step_verify!
      expect(triage[:template_namespace]).to contain_exactly(".rubocop.yml", "theme.js")
      expect(triage[:live] + triage[:comment]).not_to include(".rubocop.yml", "theme.js")
    end

    it "still flags an identity token that shares a line with a namespace" do
      run_fork(name: "my_app", yes: true)
      repo.join("theme.js").write(%(window.ModelRails.name = "modelrails_base";\n))
      git("add", "theme.js")

      flow = described_class.new({}, root: repo.to_s, output: printed)

      expect(flow.step_verify![:live]).to include("theme.js")
    end

    it "classifies a comment-only mention as harmless" do
      run_fork(name: "my_app", yes: true)
      repo.join("config/deploy.yml").write("# forked from modelrails_base\nservice: my_app\n")

      flow = described_class.new({}, root: repo.to_s, output: printed)

      expect(flow.step_verify![:comment]).to include("config/deploy.yml")
    end
  end

  # ------------------------------------------------------------------ dry run

  describe "--dry-run" do
    it "changes nothing at all" do
      before_state = [
        capture_git("rev-parse", "HEAD"),
        capture_git("status", "--porcelain"),
        capture_git("remote", "-v"),
        Dir.glob(repo.join("**/*"), File::FNM_DOTMATCH).sort.join("\n")
      ]

      run_fork(name: "my_app", preset: "none", dry_run: true, yes: true)

      after_state = [
        capture_git("rev-parse", "HEAD"),
        capture_git("status", "--porcelain"),
        capture_git("remote", "-v"),
        Dir.glob(repo.join("**/*"), File::FNM_DOTMATCH).sort.join("\n")
      ]
      expect(after_state).to eq(before_state)
    end

    it "runs on a dirty tree without aborting" do
      repo.join("uncommitted.txt").write("wip")

      expect { run_fork(name: "my_app", dry_run: true, yes: true) }.not_to raise_error
    end
  end

  # A fake shell: running bundle install and db:prepare inside an example would be absurd.
  describe "offering to start the app" do
    it "replaces bin/fork with the command, in the repo, with the clean git env" do
      allow(Kernel).to receive(:exec)

      ForkFlow::Shell.new(root: repo.to_s, dry_run: false, output: printed).exec({ "DEV_OPEN_PATH" => "/x" }, "bin/dev")

      expect(Kernel).to have_received(:exec).with(ForkFlow::CLEAN_GIT_ENV.merge("DEV_OPEN_PATH" => "/x"), "bin/dev", chdir: repo.to_s)
    end

    let(:shell) { instance_double(ForkFlow::Shell, run: true, exec: nil) }
    let(:quickstart_env) { { "DEV_OPEN_PATH" => "/docs/developer/quickstart" } }

    def flow_for(opts, input = terminal)
      described_class.new(opts, root: repo.to_s, input:, output: printed, shell:)
    end

    def answering(typed) = flow_for({ name: "my_app" }, terminal(typed))

    it "offers to start the app once setup succeeded, and execs bin/dev opening the quickstart" do
      answering("\n").offer_start!

      expect(shell).to have_received(:exec).with(quickstart_env, "bin/dev")
    end

    it "says step 1 is done and step 2's setup ran before opening" do
      answering("y\n").offer_start!

      expect(printed.string).to include("Step 1 is done and step 2's setup ran; opening the quickstart.")
    end

    it "doesn't start anything when declined" do
      answering("n\n").offer_start!

      expect(shell).not_to have_received(:exec)
      expect(printed.string).not_to include("opening the quickstart")
    end

    it "doesn't offer when setup didn't succeed" do
      run_fork({ name: "my_app", github: false }, terminal("\n" * 10)) do |flow|
        allow(flow).to receive(:offer_setup!).and_return(false)
        expect(flow).not_to receive(:offer_start!)
      end
    end

    it "offers once setup succeeded, after the summary" do
      run_fork({ name: "my_app", github: false }, terminal("\n" * 10)) do |flow|
        allow(flow).to receive(:offer_setup!).and_return(true)
        expect(flow).to receive(:offer_start!) { printed.puts("START OFFER") }
      end

      expect(printed.string.index("START OFFER")).to be > printed.string.index("Before you deploy")
    end

    [ { yes: true }, { dry_run: true } ].each do |opts|
      it "doesn't offer under #{opts.keys.first}" do
        input = terminal("y\n")

        flow_for({ name: "my_app", **opts }, input).offer_start!

        expect(input.pos).to eq(0)
        expect(shell).not_to have_received(:exec)
      end
    end

    it "doesn't offer without a terminal" do
      input = StringIO.new("y\n")

      flow_for({ name: "my_app" }, input).offer_start!

      expect(input.pos).to eq(0)
      expect(shell).not_to have_received(:exec)
    end
  end

  describe "offering bin/setup" do
    let(:shell) { instance_double(ForkFlow::Shell, run: true) }

    def flow_for(opts, input = terminal)
      described_class.new(opts, root: repo.to_s, input:, output: printed, shell:)
    end

    it "does not offer under --yes, so scripts and orchestrators stay deterministic" do
      flow_for(name: "my_app", yes: true).offer_setup!

      expect(shell).not_to have_received(:run)
    end

    it "does not offer when stdin is not a terminal" do
      flow_for({ name: "my_app" }, StringIO.new).offer_setup!

      expect(shell).not_to have_received(:run)
    end

    it "does not offer under --dry-run" do
      flow_for(name: "my_app", dry_run: true).offer_setup!

      expect(shell).not_to have_received(:run)
    end

    context "when interactive" do
      def answering(typed) = flow_for({ name: "my_app" }, terminal(typed))

      # --skip-server matters: bin/setup ends with `exec bin/dev`, which would
      # replace this process and launch a server nobody asked for.
      it "runs bin/setup without starting the dev server when accepted" do
        answering("\n").offer_setup! # bare Enter takes the default

        expect(shell).to have_received(:run).with("bin/setup", "--skip-server")
      end

      it "does nothing when declined" do
        answering("n\n").offer_setup!

        expect(shell).not_to have_received(:run)
      end

      it "reports success when bin/setup ran and passed" do
        expect(answering("y\n").offer_setup!).to be(true)
      end

      it "reports no success when declined" do
        expect(answering("n\n").offer_setup!).to be(false)
      end

      it "reports no success when bin/setup fails" do
        allow(shell).to receive(:run).and_return(false)

        expect(answering("y\n").offer_setup!).to be(false)
      end

      # The fork is committed before setup is even offered, so a setup failure
      # must not send anyone back to re-run bin/fork.
      it "reports that the fork itself is already committed when setup fails" do
        allow(shell).to receive(:run).and_return(false)

        answering("y\n").offer_setup!

        expect(printed.string).to match(/already committed/i).and match(/re-run bin\/setup/i)
      end
    end
  end

  describe ForkFlow::GithubRepo do
    it "lists the steps by hand, quietly, when told not to publish" do
      todos = []
      github = described_class.new(
        { github: false }, root: repo.to_s, snake: "my_app", branch: "next", origin_present: false, todos:,
        console: ForkFlow::Console.new(input: StringIO.new, output: printed, dry_run: false, yes: true),
        shell: ForkFlow::Shell.new(root: repo.to_s, dry_run: false, output: printed)
      )

      expect(github.publish).to be(false)
      expect(todos.join).to include("git remote add origin git@github.com:YOU/my_app.git")
      expect(printed.string).to be_empty
    end
  end

  describe ForkFlow::Console do
    def console(input, yes: false, dry_run: false) = described_class.new(input:, output: printed, yes:, dry_run:)

    it "takes the default without asking under --yes" do
      input = terminal("other\n")

      expect(console(input, yes: true).ask("Name?", "my_app")).to eq("my_app")
      expect(input.pos).to eq(0)
    end

    it "still prompts at a terminal under --dry-run, but isn't interactive" do
      dry_run = console(terminal, dry_run: true)

      expect([ dry_run.prompts?, dry_run.interactive? ]).to eq([ true, false ])
    end
  end

  describe ForkFlow::Shell do
    def shell(dry_run: false) = described_class.new(root: repo.to_s, dry_run:, output: printed)

    it "clears an inherited GIT_DIR from what it runs" do
      inherited = ENV["GIT_DIR"]
      ENV["GIT_DIR"] = workdir.join("elsewhere").to_s

      expect(shell.run("sh", "-c", 'test -z "$GIT_DIR"')).to be(true)
    ensure
      ENV["GIT_DIR"] = inherited
    end

    it "runs in the fork's root" do
      shell.run("sh", "-c", "pwd -P > where.txt")

      expect(repo.join("where.txt").read.strip).to eq(repo.realpath.to_s)
    end

    it "prints a command under --dry-run and runs nothing" do
      shell(dry_run: true).run!("touch", "made.txt")

      expect(repo.join("made.txt")).not_to exist
      expect(printed.string).to include("$ touch made.txt")
    end
  end

  describe "answering the questions" do
    it "takes the preset from the input it is given" do
      run_fork({ name: "my_app", github: false }, terminal("\n2\n")) do |flow|
        allow(flow).to receive(:offer_setup!).and_return(false)
      end

      expect(repo.join(".env").read).to include("WORKSPACE_ON_SIGNUP=shared")
    end

    def fork_config = YAML.safe_load(repo.join(".fork.yml").read)

    def answer_interactively(typed)
      run_fork({ github: false }, terminal(typed)) do |flow|
        allow(flow).to receive(:offer_setup!).and_return(false)
      end
    end

    it "writes the confirmed display name to the brand, the manifest and .fork.yml" do
      run_fork(name: "acmegarden", display_name: "Acme Garden", yes: true)

      expect(repo.join("config/locales/en/brand.en.yml").read).to include(%(name: "Acme Garden"))
      expect(repo.join("public/manifest.webmanifest").read).to include(%("Acme Garden"))
      expect(fork_config["product_name"]).to eq("Acme Garden")
    end

    it "asks for the display name after the project name, defaulting to the derived title" do
      answer_interactively("acmegarden\n\n\n\n")

      expect(printed.string).to include("Display name? [Acmegarden]")
      expect(fork_config["product_name"]).to eq("Acmegarden")
    end

    it "asks for the display name at a terminal even when --name is given" do
      run_fork({ name: "acmegarden", github: false }, terminal("Acme Garden\n\n\n")) do |flow|
        allow(flow).to receive(:offer_setup!).and_return(false)
      end

      expect(fork_config["product_name"]).to eq("Acme Garden")
    end

    it "strips whitespace from the display name" do
      answer_interactively("acmegarden\n  Acme Garden  \n\n\n")

      expect(fork_config["product_name"]).to eq("Acme Garden")
    end

    it "asks again when the display name contains a double quote or backslash" do
      answer_interactively(%(acmegarden\nBob "Shop"\nBob Shop\n\n\n))

      expect(printed.string).to include(%(Display name can't contain " or \\))
      expect(fork_config["product_name"]).to eq("Bob Shop")
    end

    it "refuses a --display-name containing a double quote or backslash" do
      expect { run_fork(name: "acmegarden", display_name: %(Bob "Shop"), yes: true) }
        .to raise_error(SystemExit, /Display name can't contain " or \\/)
    end
  end

  describe "the ending of a fresh fork" do
    let(:quickstart) { "http://localhost:3000/docs/developer/quickstart" }

    def run_with_setup(result = true, &)
      run_fork({ name: "my_app", github: false }, terminal("\n" * 10)) do |flow|
        allow(flow).to receive(:offer_setup!) { printed.puts("SETUP OUTPUT") if result; result }
        allow(flow).to receive(:offer_start!)
      end
    end

    it "prints Next steps after bin/setup's output" do
      run_with_setup

      expect(printed.string.index("Next steps")).to be > printed.string.index("SETUP OUTPUT")
    end

    it "opens Next steps with the quickstart's full URL" do
      run_fork(name: "my_app", yes: true)

      expect(printed.string).to match(%r{Next steps ==\n\s*Follow the quickstart: #{quickstart}})
      expect(printed.string).not_to include("deploy-guide")
    end

    it "gives the quickstart on the port bin/dev will choose when 3000 is taken" do
      allow(DevPort).to receive(:busy?).with(3000).and_return(true)

      run_fork(name: "my_app", yes: true)

      expect(printed.string).to include("Follow the quickstart: http://localhost:3001/docs/developer/quickstart")
      expect(printed.string).to include("http://localhost:3001/docs/developer/presets")
    end

    it "names bin/production-setup for step 4, even with --yes" do
      run_fork(name: "my_app", yes: true)

      expect(printed.string).to include("Before you deploy: bin/production-setup sets up production's secrets: mail, encryption keys and fnox (quickstart step 4)")
    end

    it "never asks about mail" do
      run_with_setup

      expect(printed.string).not_to include("Set up outbound mail now?")
    end

    it "no longer tells you to run bin/setup when it just ran" do
      run_with_setup

      expect(printed.string).not_to include("bin/setup --skip-server && bin/parallel-rspec")
      expect(printed.string).not_to include("Run bin/setup, then bin/dev")
    end

    it "tells you to run bin/setup, then bin/dev, when setup didn't run" do
      run_fork(name: "my_app", yes: true)

      expect(printed.string.lines.last).to include("Run bin/setup, then bin/dev")
    end

    it "lists copywriting under Make it yours, after the fork's own to-dos" do
      run_fork(name: "my_app", yes: true)
      output = printed.string

      expect(output.index("Make it yours:")).to be > output.index("  1. ")
      expect(output.index("Rewrite marketing copy")).to be > output.index("Make it yours:")
    end

    it "says what to make yours without calling it fork-owned" do
      run_fork(name: "my_app", yes: true)
      repo.join("README.md").write("# modelrails_base\n")
      system(ForkFlow::CLEAN_GIT_ENV, "git", "-C", repo.to_s, "add", "README.md", exception: true)
      flow = described_class.new({}, root: repo.to_s, output: printed)
      flow.step_verify!

      expect(printed.string[printed.string.index("Make it yours:")..]).to include("_site_mark", "vocabulary.local.yml")
      expect(flow.make_it_yours.join).to include("README.md")
      expect(printed.string + flow.make_it_yours.join).not_to include("fork-owned")
    end

    it "points a skipped preset at the presets page without warning about migrations" do
      run_fork(name: "my_app", yes: true)

      expect(printed.string).not_to include("migration, not a config flip")
      expect(printed.string).to include("http://localhost:3000/docs/developer/presets")
    end

    it "keeps Verify's pass line and drops the comment-only file list" do
      repo.join("config/notes.yml").write("# forked from modelrails_base\nkey: value\n")
      git("add", "config/notes.yml")
      git("commit", "-qm", "add a comment-only mention")

      run_fork(name: "my_app", yes: true)

      expect(printed.string).to include("no live template tokens")
      expect(printed.string).not_to include("comment-only mentions")
    end
  end

  describe "a hand-edited .fork.yml" do
    it "names the file and the fix when it isn't valid YAML" do
      run_fork(name: "my_app", yes: true)
      repo.join(".fork.yml").write("name: [unclosed\n")
      git("commit", "-qam", "break it")

      expect { run_fork(yes: true) }.to raise_error(SystemExit).and output(/\.fork\.yml is not valid YAML.*Fix it by hand/m).to_stderr
    end
  end

  describe "provenance" do
    # .fork.yml is committed and hand-editable, so it will be hand-edited.
    it "reports a corrupt .fork.yml instead of raising Psych internals" do
      run_fork(name: "my_app", preset: "none", yes: true)
      repo.join(".fork.yml").write("preset: [unclosed\n")

      expect { run_fork(preset: "none", yes: true) }.to raise_error(SystemExit)
    end

    it "refuses a hand-edited preset the app would not boot on" do
      run_fork(name: "my_app", preset: "none", yes: true)
      repo.join(".fork.yml").write("preset: personl\nname: my_app\n")

      expect { run_fork(preset: "personl", yes: true) }.to raise_error(SystemExit)
    end
  end

  describe "preflight" do
    # A fresh laptop, a container, or a CI runner may have no git identity. The
    # script commits on the user's behalf, so it must say so up front rather
    # than dying on `fatal: empty ident name` after the remote surgery.
    it "refuses, without mutating, when git has no identity configured" do
      # Blanked locally rather than unset: unsetting would still fall through to
      # the developer's global identity, making this pass or fail depending on
      # whose machine it runs on — the very class of bug this example exists for.
      git("config", "user.email", "")
      git("config", "user.name", "")

      expect { run_fork(name: "my_app", yes: true) }.to raise_error(SystemExit)
      expect(repo.join("config/application.rb").read).to include("module ModelrailsBase")
      expect(capture_git("remote")).to eq("origin")
    end

    it "refuses a dirty working tree" do
      repo.join("uncommitted.txt").write("wip")

      expect { run_fork(name: "my_app", yes: true) }.to raise_error(SystemExit)
    end
  end
end
