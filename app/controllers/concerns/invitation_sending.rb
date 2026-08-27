# frozen_string_literal: true

# Gates every surface that sends an invitation on the sender having PROVEN
# their own address (D5).
#
# One concern rather than a per-controller check because there are four create
# paths — workspace invitations, project invitations, client invitations, and
# onboarding — and a gate that covers some of them is decorative. A fork adding
# a fifth surface includes this and gets the gate; forgetting to is the failure
# this shape is meant to make unlikely.
#
# `can_invite?` is an existence check over verified authentications, which is
# only trustworthy because every writer of `verified_at` demonstrates control
# of the mailbox. See User#can_invite? and the writer inventory in
# spec/requests/can_invite_gate_spec.rb.
module InvitationSending
  extend ActiveSupport::Concern

  included do
    before_action :require_verified_sender!, only: :create
  end

  private

  def require_verified_sender!
    return if Current.user&.can_invite?

    respond_to do |format|
      format.html do
        redirect_back fallback_location: root_path,
                      alert: t("invitations.unverified_sender")
      end
      format.turbo_stream do
        redirect_back fallback_location: root_path,
                      alert: t("invitations.unverified_sender")
      end
    end
  end
end
