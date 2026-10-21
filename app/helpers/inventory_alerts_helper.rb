module InventoryAlertsHelper
  def alert_status_tag(inventory_alert)
    if inventory_alert.open?
      tag.span "Open", class: "status status--open"
    else
      tag.span "Resolved", class: "status status--resolved"
    end
  end

  # A brand's open-alert count, linked to those alerts. Zero stays plain text,
  # since the link would lead to an empty list.
  def open_alerts_link(brand, count)
    return number_with_delimiter(count) if count.zero?

    link_to number_with_delimiter(count), inventory_alerts_path(brand_id: brand.id, status: "open")
  end
end
