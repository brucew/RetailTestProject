class PriceChecksController < ApplicationController
  def index
    @product = Product.find(params[:product_id])
    @pagy, @price_checks = pagy(@product.price_checks.includes(:store).newest_first)
  end
end
