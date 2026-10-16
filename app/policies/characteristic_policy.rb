class CharacteristicPolicy < ApplicationPolicy
  def index? = user.present?
end
