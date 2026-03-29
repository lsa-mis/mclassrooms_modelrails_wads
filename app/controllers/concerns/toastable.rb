module Toastable
  extend ActiveSupport::Concern

  private

  def toast_stream(type, message, target: "notifications")
    turbo_stream.append(target, partial: "shared/toast", locals: { type: type, message: message })
  end

  def success_toast(message)
    toast_stream("success", message)
  end

  def error_toast(message)
    toast_stream("error", message)
  end
end
