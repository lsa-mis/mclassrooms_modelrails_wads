require "rails_helper"

RSpec.describe "Bullet" do
  it "runs in the test suite with its Active Record patches loaded" do
    expect(Bullet.enable?).to be(true)
    expect(Bullet::ActiveRecord).to be_a(Module)
  end

  it "catches an N+1 query on this Active Record" do
    create_list(:building, 2)
    Bullet.end_request
    Bullet.start_request
    Building.all.each { |building| building.workspace.name }

    expect(Bullet.notification?).to be(true)
  ensure
    Bullet.end_request
    Bullet.start_request
  end
end
