class ProductsController < ApplicationController
  def index
    @products = Product.includes(:brand).order(:name)
    @check_counts = InventoryCheck.group(:product_id).count
  end

  def show
    @product = Product.includes(:brand).find(params[:id])
    @current_prices = @product.price_checks.latest_per_store_and_product
                              .eager_load(:store).merge(Store.order(:address)).load
    checks = @product.inventory_checks.includes(:store).newest_first
    @pagy, @inventory_checks = pagy(checks)
  end
end
