class StoresController < ApplicationController
  def index
    @stores = Store.order(:address)
    @check_counts = InventoryCheck.group(:store_id).count
  end

  def show
    @store = Store.find(params[:id])
    # Not paginated: one row per product, so the catalog (226 products), not
    # the price history, bounds its length.
    @current_prices = @store.price_checks.latest_per_store_and_product
                            .includes(product: :brand).merge(Product.order(:name))
    checks = @store.inventory_checks.includes(product: :brand).newest_first
    @pagy, @inventory_checks = pagy(checks)
  end
end
