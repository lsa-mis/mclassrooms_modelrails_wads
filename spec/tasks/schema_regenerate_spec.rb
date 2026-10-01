require "rails_helper"

# The connected database is pointed at an empty file, so a task that dumped it
# instead of migrating a scratch one would write an empty schema.
RSpec.describe "db:schema:regenerate", type: :task do
  let(:output) { Rails.root.join("tmp/regenerated_schema_#{ENV.fetch('TEST_ENV_NUMBER', '')}.rb") }
  let(:empty_db) { Rails.root.join("tmp/regenerate_empty_#{ENV.fetch('TEST_ENV_NUMBER', '')}.sqlite3") }

  after { FileUtils.rm_f([ output, empty_db ]) }

  it "writes db/schema.rb from db/migrate alone, byte for byte what the checkout commits" do
    env = { "SCHEMA" => output.to_s, "DATABASE_URL" => "sqlite3:#{empty_db}" }
    log = IO.popen(env, [ Rails.root.join("bin/rails").to_s, "db:schema:regenerate" ], err: [ :child, :out ], &:read)

    expect($?.exitstatus).to eq(0), "db:schema:regenerate failed:\n#{log}"
    expect(output.read).to eq(Rails.root.join("db/schema.rb").read)
  end
end
