class ProductsController < ApplicationController
  def index
    @products = Product.all
  end

  def show
    @product = Product.includes(:brand).find(params[:id])
    # id breaks ties between same-day checks: the later CSV row is the newer one (D6).
    checks = @product.inventory_checks.includes(:store).order(event_time: :desc, id: :desc)
    @pagy, @inventory_checks = pagy(checks)
  end
end
