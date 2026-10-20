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
    price_history = @product.price_checks.includes(:store).newest_first
    # A page param of its own, so paging one list never moves the other.
    @price_pagy, @price_checks = pagy(price_history, page_param: :price_page)
  end
end
