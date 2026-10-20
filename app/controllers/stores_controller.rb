class StoresController < ApplicationController
  def index
    @stores = Store.order(:address)
    @check_counts = InventoryCheck.group(:store_id).count
  end

  def show
    @store = Store.find(params[:id])
    checks = @store.inventory_checks.includes(product: :brand).newest_first
    @pagy, @inventory_checks = pagy(checks)
  end
end
