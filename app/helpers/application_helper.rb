module ApplicationHelper
  include Pagy::Frontend

  # Links to a top-level section, marked as the current page (for styling and
  # screen readers) while any page of that section's controller is shown.
  def section_link_to(name, path, section)
    link_to name, path, class: "site-nav__link", aria: { current: ("page" if controller_name == section) }
  end

  # Checks are recorded per day and stored as midnight UTC, and alert times
  # are copied from checks, so only the date carries information. Converting
  # from UTC first keeps a non-UTC app time zone from shifting every date
  # onto the previous day.
  def utc_date_tag(time)
    date = time.utc.to_date
    time_tag date, date.iso8601
  end
end
