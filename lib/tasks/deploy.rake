namespace :deploy do
  desc "List everything that would stop production booting, before you deploy; DESTINATION=staging checks staging"
  task check: :environment do
    exit DeployCheck.new(root: Rails.root, destination: ENV["DESTINATION"], compact: ENV["DEPLOY_CHECK_COMPACT"] == "1").run
  end
end
