# Form object for the feedback surface. ActiveModel::Model gives the `errors`
# API TailwindFormBuilder expects, so the view renders via `form_with model:`
# and inherits the auto-applied error classes, ARIA, inline messages, and value
# preservation on re-render without re-implementing them in the template. Not
# persisted — FeedbacksController hands its fields to Feedback::Submit.
class FeedbackForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  # Namespace params/field ids as `feedback[...]` (not the class-derived
  # `feedback_form[...]`), matching FeedbacksController + the singular route.
  def self.model_name = ActiveModel::Name.new(self, nil, "Feedback")

  attribute :message, :string
  attribute :email, :string
  attribute :category, :string

  validates :message, presence: { message: ->(_object, _data) { I18n.t("feedback.errors.blank_message") } }
end
