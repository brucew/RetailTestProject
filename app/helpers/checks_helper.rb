# Formatting shared by every kind of check (inventory and price).
module ChecksHelper
  # Checks are recorded per day and stored as midnight UTC, so only the date
  # carries information. Converting from UTC first keeps a non-UTC app time
  # zone from shifting every check onto the previous day.
  def check_date_tag(check)
    date = check.event_time.utc.to_date
    time_tag date, date.iso8601
  end
end
