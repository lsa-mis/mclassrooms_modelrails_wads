# MiClassrooms Phase 3 Task 7 (Brief §5.1): the filters glossary — a
# single headless action rendering every characteristic short-code +
# long description, grouped and alphabetized by CharacteristicFilterGroups.
# CharacteristicPolicy#glossary? is `user.present?` only (no record to
# scope), so `authorize :characteristic, :glossary?` is what satisfies
# ApplicationController's `verify_authorized` after_action.
class CharacteristicsController < ApplicationController
  include DirectoryScoped

  def glossary
    authorize :characteristic, :glossary?
    @groups = CharacteristicFilterGroups.glossary
  end
end
