# frozen_string_literal: true

namespace :erb do
  desc "Check ERB files for lint violations"
  task :lint do
    files = Dir.glob("app/**/*.erb")
    if files.empty?
      puts "No ERB files found"
    else
      sh "bundle exec erb_lint --lint-all"
    end
  end

  desc "Check ERB files for lint violations (CI — aborts on failure)"
  task :check do
    files = Dir.glob("app/**/*.erb")
    abort "No ERB files found" if files.empty?
    sh "bundle exec erb_lint --lint-all"
  end
end
