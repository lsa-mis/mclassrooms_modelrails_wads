RSpec.configure do |config|
  config.before(:each) do
    pwned = instance_double(Pwned::Password, pwned?: false)
    allow(Pwned::Password).to receive(:new).and_return(pwned)
  end
end
