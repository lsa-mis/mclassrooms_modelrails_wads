class CheckGravatarJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  def perform(user)
    has_gravatar = gravatar_exists?(user.email_address)
    user.update_columns(has_gravatar: has_gravatar, updated_at: Time.current)
  end

  private

  def gravatar_exists?(email)
    hash = Digest::SHA256.hexdigest(EmailNormalizer.normalize(email))
    uri = URI("https://www.gravatar.com/avatar/#{hash}?d=404")
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 5) do |http|
      http.head(uri.request_uri)
    end
    response.code == "200"
  rescue StandardError
    false
  end
end
