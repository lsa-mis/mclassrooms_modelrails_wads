RSpec.configure do |config|
  config.before(:each) do
    allow_any_instance_of(Pwned::Password).to receive(:pwned?).and_return(false)
  end
end
