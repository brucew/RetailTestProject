module InventoryAlertsHelper
  def alert_status_tag(inventory_alert)
    if inventory_alert.open?
      tag.span "Open", class: "status status--open"
    else
      tag.span "Resolved", class: "status status--resolved"
    end
  end
end
