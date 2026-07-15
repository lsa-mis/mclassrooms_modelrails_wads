# frozen_string_literal: true

namespace :markdown do
  desc "Auto-fix markdown issues, then check for remaining violations"
  task :lint do
    sh "bundle exec mdl --fix --git-recurse ."
    sh "bundle exec mdl --git-recurse ."
  end

  desc "Check markdown for violations (CI — no auto-fix)"
  task :check do
    sh "bundle exec mdl --git-recurse ."
  end
end
