class ApplicationController < ActionController::Base
  include Pagy::Backend

  private

  # Pagy's documented hook for reading the page. A page sent as an array or
  # hash (?page[]=2) is a malformed request, like ?page=abc, rather than a
  # server error.
  def pagy_get_page(vars, force_integer: true)
    page = params[vars[:page_param] || Pagy::DEFAULT[:page_param]]
    raise ActionController::BadRequest, "page must be a single value" unless page.nil? || page.is_a?(String)

    super
  end
end
