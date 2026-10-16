class CharacteristicsController < ApplicationController
  include DirectoryScoped
  include PublicDirectoryChrome

  def index
    authorize :characteristic
    @groups = CharacteristicFilterGroups.glossary
  end
end
