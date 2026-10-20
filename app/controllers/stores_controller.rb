class StoresController < ApplicationController
  def index
    @stores = Store.order(:address)
    @check_counts = InventoryCheck.group(:store_id).count
  end

  def show
    @store = Store.find(params[:id])
    # id breaks ties between same-day checks: the later CSV row is the newer one (D6).
    checks = @store.inventory_checks.includes(product: :brand).order(event_time: :desc, id: :desc)
    @pagy, @inventory_checks = pagy(checks)
  end
end
