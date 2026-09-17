module Operations
  class OperatorshipsController < BaseController
    def index
      authorize [ :operations, Operatorship ]
      @operatorships = Operatorship.kept.includes(:user, :granted_by).order(:created_at)
    end

    def create
      authorize [ :operations, Operatorship ]
      email = params[:email].to_s.strip
      # Own branch, own posture-neutral copy: a blank submission must not
      # fall into the not_found branch and blame an email nobody typed. Also
      # keeps this request-spec-testable, unlike relying on the input's
      # `required` attribute alone.
      if email.blank?
        redirect_to operations_operatorships_path, alert: t(".blank")
        return
      end
      user = User.find_by(email_address: email)
      if user.nil?
        redirect_to operations_operatorships_path, alert: t(".not_found")
      elsif user.operator?
        redirect_to operations_operatorships_path, notice: t(".already")
      else
        # Rescued inline, not with a model uniqueness validation: the partial
        # unique index is the real guarantee under concurrency, and a double
        # submit racing the operator? check above is the only way to reach
        # it — the ordinary sequential path never does. Kept inside #create
        # (not a private helper) so the lazy t(".key") lookups below still
        # scope to this action.
        begin
          Operatorship.grant!(user: user, granted_by: Current.user)
          redirect_to operations_operatorships_path, notice: t(".success")
        rescue ActiveRecord::RecordNotUnique
          redirect_to operations_operatorships_path, notice: t(".already")
        end
      end
    end

    # The last kept operatorship can't be revoked from the panel — the guard
    # lives in Operatorship#revoke_by_operator!, not here: a bare count
    # check outside a transaction would let two operators revoking two
    # DIFFERENT rows both pass. `rails operators:revoke` still calls plain
    # `revoke!` (break-glass), keeping its documented ability to remove the
    # last one.
    #
    # Unscoped find, not `.kept`: a replayed delete must reach
    # revoke_by_operator!'s own discarded? branch instead of 404ing first.
    def destroy
      operatorship = Operatorship.find(params[:id])
      authorize [ :operations, operatorship ]
      case operatorship.revoke_by_operator!(Current.user)
      when :revoked then redirect_to operations_operatorships_path, notice: t(".success")
      when :already_revoked then redirect_to operations_operatorships_path, alert: t(".already_revoked")
      when :last_operator then redirect_to operations_operatorships_path, alert: t(".last_operator")
      when :self_revoke then redirect_to operations_operatorships_path, alert: t(".self_revoke")
      end
    end
  end
end
