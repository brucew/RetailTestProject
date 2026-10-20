module InventoryChecksHelper
  # Checks are recorded per day and stored as midnight UTC, so only the date
  # carries information. Converting from UTC first keeps a non-UTC app time
  # zone from shifting every check onto the previous day.
  def check_date_tag(inventory_check)
    date = inventory_check.event_time.utc.to_date
    time_tag date, date.iso8601
  end

  def inventory_status_tag(inventory_check)
    if inventory_check.inventory_present
      tag.span "In stock", class: "status status--in-stock"
    else
      tag.span "Out of stock", class: "status status--out-of-stock"
    end
  end
end
