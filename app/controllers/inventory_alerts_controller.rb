class InventoryAlertsController < ApplicationController
  def index
    alerts = InventoryAlert.for_brand(params[:brand_id]).with_status(params[:status])
                           .includes(:brand, :store, :product).newest_first
    @pagy, @inventory_alerts = pagy(alerts)
    @brands = Brand.order(:name)
  end

  def show
    @inventory_alert = InventoryAlert.find(params[:id])
    @streak_checks = @inventory_alert.streak_checks
  end
end
