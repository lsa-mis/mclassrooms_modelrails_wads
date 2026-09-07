# The email a visitor typed to start signing in (the lookup step of Sessions::LookupsController).
# Uses ActiveModel::Model to provide the standard `errors` API that
# TailwindFormBuilder expects, so the view can render via `form_with model:`
# and inherit auto-applied error classes, ARIA attributes, and inline error
# messages without re-implementing them in the template.
class EmailLookup
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :email_address, :string

  # Both presence and format use the same user-facing message so blank email,
  # missing email, and malformed email all render the unified "please enter a
  # valid email address" notice. (Without the custom message on presence, blank
  # input would surface the default "can't be blank" string and the test
  # assertion at spec/requests/sessions/lookups_spec.rb would diverge.)
  EMAIL_LOOKUP_INVALID_MESSAGE = ->(_object, _data) { I18n.t("sessions.lookups.create.invalid_email") }

  validates :email_address,
            presence: { message: EMAIL_LOOKUP_INVALID_MESSAGE },
            format: { with: User::EMAIL_FORMAT, message: EMAIL_LOOKUP_INVALID_MESSAGE }
end
