# MiClassrooms Phase 3 Task 7 (Brief §5.1): the filters glossary — a
# single headless action rendering every characteristic short-code +
# long description, grouped and alphabetized by CharacteristicFilterGroups.
# CharacteristicPolicy#glossary? is `user.present?` only (no record to
# scope). This action has no record to authorize against, so it calls
# `authorize :characteristic, :glossary?` explicitly itself — there is no
# app-wide `after_action :verify_authorized` backstop in
# ApplicationController that would otherwise catch a missing authorize call.
class CharacteristicsController < ApplicationController
  include DirectoryScoped

  def glossary
    authorize :characteristic, :glossary?
    @groups = CharacteristicFilterGroups.glossary
  end
end
