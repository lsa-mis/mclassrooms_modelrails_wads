# frozen_string_literal: true

namespace :markdown do
  desc "Auto-fix markdown issues, then check for remaining violations"
  task :lint do
    sh "markdownlint --fix '**/*.md'"
    sh "markdownlint '**/*.md'"
  end

  desc "Check markdown for violations (CI — no auto-fix)"
  task :check do
    sh "markdownlint '**/*.md'"
  end
end
