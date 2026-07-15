require "rails_helper"

RSpec.describe "config/database.yml" do
  # Render the ERB template under a controlled TEST_ENV_NUMBER, restoring the
  # real value afterwards (this spec itself runs inside a parallel worker).
  def test_database_path(test_env_number)
    original = ENV["TEST_ENV_NUMBER"]
    if test_env_number.nil?
      ENV.delete("TEST_ENV_NUMBER")
    else
      ENV["TEST_ENV_NUMBER"] = test_env_number
    end
    raw = File.read(Rails.root.join("config/database.yml"))
    YAML.safe_load(ERB.new(raw).result, aliases: true).dig("test", "database")
  ensure
    original.nil? ? ENV.delete("TEST_ENV_NUMBER") : ENV["TEST_ENV_NUMBER"] = original
  end

  it "gives each parallel worker its own SQLite file" do
    expect(test_database_path("2")).to eq("storage/test2.sqlite3")
  end

  it "keeps the canonical path for single-process runs" do
    expect(test_database_path(nil)).to eq("storage/test.sqlite3")
  end

  it "keeps the canonical path for parallel worker 1 (TEST_ENV_NUMBER is empty)" do
    expect(test_database_path("")).to eq("storage/test.sqlite3")
  end
end
