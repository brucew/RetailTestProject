module InventoryChecksHelper
  def inventory_status_tag(inventory_check)
    if inventory_check.inventory_present
      tag.span "In stock", class: "status status--in-stock"
    else
      tag.span "Out of stock", class: "status status--out-of-stock"
    end
  end
end
