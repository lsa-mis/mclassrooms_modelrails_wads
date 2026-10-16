class Buildings::HidingsController < ApplicationController
  include DirectoryScoped

  before_action :set_building

  def create
    authorize @building, :hide?
    @building.hide!(actor: Current.user)
    redirect_to building_path(@building), notice: t("buildings.hide.success")
  end

  def destroy
    authorize @building, :unhide?
    @building.unhide!(actor: Current.user)
    redirect_to building_path(@building), notice: t("buildings.unhide.success")
  end

  private

  def set_building
    @building = Building.for_current_workspace.find_by!(bldrecnbr: params[:building_id])
  end
end
