class ProductsController < ApplicationController
  def index
    @products = Product.includes(:brand).order(:name)
    @check_counts = InventoryCheck.group(:product_id).count
  end

  def show
    @product = Product.includes(:brand).find(params[:id])
    checks = @product.inventory_checks.includes(:store).newest_first
    @pagy, @inventory_checks = pagy(checks)
  end
end
