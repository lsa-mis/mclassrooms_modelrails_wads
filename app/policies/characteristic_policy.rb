# MiClassrooms Phase 3 Task 1 (spec D5): authorizes the characteristic
# glossary + filter data backing the Find a Room screen. Headless — there's
# no single Characteristic record, so controllers call
# `authorize :characteristic, :glossary?` and `record` is just that symbol.
# No mutations this phase; ApplicationPolicy's default-false covers those.
class CharacteristicPolicy < ApplicationPolicy
  def index? = user.present?
  def glossary? = user.present?
end
