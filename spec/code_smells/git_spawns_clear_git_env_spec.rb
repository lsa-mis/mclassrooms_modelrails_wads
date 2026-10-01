require "rails_helper"

# Every git spawn under bin/ and spec/ clears the GIT_DIR family (#789, #1056).
# Reads the whole call, since the env can sit on the line after the paren.
RSpec.describe "Code smell: git spawns clear the GIT_DIR family" do
  let(:spawn_tokens) do
    %w[system system! IO.popen Open3.capture2 Open3.capture3 Open3.capture2e Process.spawn]
  end

  # Returns [offenders, env_carrying_count] for one source string.
  def scan(raw)
    # Comment lines dropped first: prose about git is not a spawn.
    source = raw.lines.reject { |line| line.strip.start_with?("#") }.join
    offenders = []
    carrying = 0

    # Quoted strings blanked first, for the same reason.
    without_strings = source.gsub(/"[^"\n]*"|'[^'\n]*'/) { |m| " " * m.length }
    without_strings.scan(/`([^`\n]*)`|%x[({\[]([^)}\]\n]*)[)}\]]/) do |backtick, percent|
      body = (backtick || percent).to_s
      offenders << body.strip if body.strip.start_with?("git ")
    end

    spawn_tokens.each do |token|
      index = 0
      while (found = source.index("#{token}(", index))
        index = found + token.length
        open_paren = found + token.length
        close = balanced_end(source, open_paren)
        next unless close

        args = source[(open_paren + 1)...(close - 1)].to_s
        if args.match?(/clean_?git_?env/i)
          carrying += 1
          next
        end

        first = args.lstrip
        git = first.start_with?('"git"', "'git'", '"git ', "'git ") ||
              first.match?(/\A\[\s*["']git["']/)
        offenders << args.split("\n").first.to_s.strip if git
      end
    end

    [ offenders, carrying ]
  end

  def source_files
    (Dir[Rails.root.join("bin/*")].select { |f| File.file?(f) } +
      Dir[Rails.root.join("spec/**/*.rb")])
      .reject { |f| f.end_with?("spec/code_smells/git_spawns_clear_git_env_spec.rb") }
  end

  # POSITIVE CONTROL 1: a walker that sees nothing must not pass.
  it "sees the git spawns that already carry the env" do
    carrying = source_files.sum { |f| scan(File.read(f)).last }

    expect(carrying).to be >= 11,
      "only #{carrying} env-carrying git spawns were recognised — the scanner has stopped " \
      "reading the calls it is supposed to police, so a bare spawn would pass unseen"
  end

  # POSITIVE CONTROL 2 — every bare shape is caught, including the multi-line one.
  it "catches each bare spawn shape, and clears each guarded one" do
    bare = <<~RUBY
      system("git", "status")
      system("git status")
      IO.popen(["git", "status"])
      Open3.capture2("git", "status")
      `git status`
      %x(git status)
    RUBY
    expect(scan(bare).first.size).to eq(6), "a bare shape slipped past the scanner"

    guarded = <<~RUBY
      system(CleanGitEnv::HASH, "git", "status")
      system(CleanGitEnv::HASH, "git status")
      IO.popen(CleanGitEnv::HASH, ["git", "status"])
      Open3.capture2(CleanGitEnv::HASH, "git", "status")
      IO.popen(
        ForkFlow::CLEAN_GIT_ENV,
        ["git", "status"]
      )
    RUBY
    expect(scan(guarded).first).to be_empty, "a guarded spawn was reported as an offender"
  end

  # NEGATIVE CONTROL — this is a git guard, not a no-spawns rule.
  it "ignores spawns that are not git" do
    other = <<~RUBY
      system("bundle", "exec", "rspec")
      `bin/rails runner 'puts 1'`
    RUBY
    expect(scan(other).first).to be_empty
  end

  it "finds no bare git spawn under bin/ or spec/" do
    offenders = source_files.flat_map do |file|
      relative = Pathname.new(file).relative_path_from(Rails.root).to_s
      scan(File.read(file)).first.map { |call| "#{relative}: #{call}" }
    end

    expect(offenders).to be_empty, <<~MESSAGE
      These spawn git without clearing the GIT_DIR family, so under a git hook they
      operate on the hook's repository rather than this one (#789):

        #{offenders.join("\n  ")}

      Pass CleanGitEnv::HASH (lib/clean_git_env.rb) as the first argument.
    MESSAGE
  end
end
