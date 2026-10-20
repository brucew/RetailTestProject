module ApplicationHelper
  include Pagy::Frontend

  # Links to a top-level section, marked as the current page (for styling and
  # screen readers) while any page of that section's controller is shown.
  def section_link_to(name, path, section)
    link_to name, path, class: "site-nav__link", aria: { current: ("page" if controller_name == section) }
  end
end
