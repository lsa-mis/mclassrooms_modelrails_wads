require "rails_helper"

# A foreign key into users with no posture surfaces as InvalidForeignKey on
# user.destroy; the schema is the census, so a new one cannot arrive unnoticed.
RSpec.describe "Code smell: every foreign key into users has a cleanup posture" do
  let(:schema) { Rails.root.join("db/schema.rb").read }

  let(:foreign_keys_into_users) do
    schema.scan(/add_foreign_key "(\w+)", "users"(?:, column: "(\w+)")?([^\n]*)/).map do |table, column, rest|
      { table: table, column: column || "user_id", on_delete: rest.include?("on_delete") }
    end
  end

  let(:handled_on_user) do
    (User.reflect_on_all_associations(:has_many) + User.reflect_on_all_associations(:has_one))
      .select { |reflection| reflection.options[:dependent] && !reflection.options[:through] }
      .map { |reflection| [ reflection.klass.table_name, reflection.foreign_key.to_s ] }
      .to_set
  end

  it "declares a dependent: posture on User, or on_delete in the schema, for each" do
    unhandled = foreign_keys_into_users.reject do |fk|
      fk[:on_delete] || handled_on_user.include?([ fk[:table], fk[:column] ])
    end

    expect(unhandled).to be_empty, unhandled.map { |fk|
      "#{fk[:table]}.#{fk[:column]} → users has no cleanup posture: give User a has_many or has_one " \
        "with dependent: for it, or the foreign key an on_delete:"
    }.join("\n")
  end

  it "finds the foreign keys it guards (positive control)" do
    expect(foreign_keys_into_users.map { |fk| fk[:table] }).to include("sessions", "memberships")
  end
end
