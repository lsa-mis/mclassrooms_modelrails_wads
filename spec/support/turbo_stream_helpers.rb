module TurboStreamHelpers
  def streams = Nokogiri::HTML5.fragment(response.body).css("turbo-stream")
  def stream_shape = streams.map { [ it["action"], it["target"], it["method"] ] }
end

RSpec.configure do |config|
  config.include TurboStreamHelpers, type: :request
end
