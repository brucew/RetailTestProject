class BrandsController < ApplicationController
  def index
    @brands = Brand.order(:name)
    @product_counts = Product.group(:brand_id).count
  end

  def show
    @brand = Brand.find(params[:id])
    @products = @brand.products.order(:name).load
    @check_counts = InventoryCheck.where(product: @brand.products).group(:product_id).count
  end
end
